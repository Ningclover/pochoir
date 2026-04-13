# 03 — GPU Running Efficiency

This document audits GPU utilisation across the whole pipeline, identifies host↔device
synchronisation points in the inner loop, and quantifies the Python-level overhead per
iteration.  No wall-clock profiling was performed — all findings are derived from reading
the code.

---

## 1. Headline: only the FDM step actually runs on the GPU

The `pochoir` back-end naming (`fdm --engine torch`, `drift --engine torch`) implies
GPU acceleration at each pipeline stage.  In practice:

| Command | Engine | Actual device |
|---------|--------|--------------|
| `fdm --engine numpy` | numpy | CPU |
| `fdm --engine numba` | numba | CPU (JIT) |
| `fdm --engine torch` | PyTorch CUDA | **GPU** (cuda:0) |
| `fdm --engine cupy` | CuPy | **GPU** |
| `fdm --engine cumba` | numba-CUDA | **GPU** (2D only; 3D kernel broken — see [B-A2](02-potential-bugs.md)) |
| `velo` | — | CPU (numpy.gradient + numpy.vectorize) |
| `grad` | — | CPU (numpy.gradient) |
| `drift --engine numpy` | scipy | CPU |
| `drift --engine torch` | torchdiffeq | CPU (`device='cpu'` hard-coded — see [C-5](02-potential-bugs.md)) |
| `induce` | — | CPU (scipy RGI) |
| `srdot` | — | CPU (scipy RGI) |

The FDM is the only stage that can use the GPU.  Every other stage runs entirely on the CPU,
regardless of the `--engine` flag.  Furthermore, since each CLI command is a fresh Python
process, GPU state is never preserved between commands — the GPU is allocated, used for FDM,
and released before the next command begins.

---

## 2. FDM engine efficiency audit

### 2.1 fdm_numpy

- **Stencil:** `fdm_generic.stencil` — a Python `for` loop over `2*N` tensor views
  (`fdm_generic.py:57-66`).  N calls to `res += array[...]` and one `res *= norm`.
  For 3D that is 7 numpy operations per step.
- **Allocations per step:** one fresh `core_shape` array allocated inside `stencil`
  (`fdm_generic.py:51-53`), one copy for `prev` at each epoch-last-step
  (`fdm_numpy.py:58`).
- **No GPU involved.**

### 2.2 fdm_numba

- **Stencil:** `@numba.stencil` JIT kernel called via `@numba.njit` wrapper
  (`fdm_numba.py:20-31`).  The kernel returns a full-size array (same shape as input)
  and is then sliced to core (`fdm_numba.py:33-34`).  One JIT compilation on first call,
  then fast.
- **Allocations per step:** one full-size output from `@numba.stencil` per step (numba
  stencil allocates internally).
- **No GPU.**

### 2.3 fdm_torch (GPU path)

**Stencil (Python loop on GPU tensors, `fdm_generic.py:55-66`):**

```python
res[:] = 0                  # 1 kernel launch
for dim, n in enumerate(array.shape):
    res += array[pos]        # N kernel launches
    res += array[neg]        # N kernel launches
res *= norm                 # 1 kernel launch
```

Total launches per stencil call: `2N + 2`.  For 3D: **8 kernel launches** per stencil.

**Update step (`fdm_torch.py:64`):**
```python
iarr_pad[core] = bi_core + mutable_core * tmp_core
```
Three operations: multiply (1), add (1), slice-assign (1) = ~3 kernel launches.

**Edge condition (`fdm_generic.py:27-29`):** Each dimension touches 2 slices = `2N` assign
operations.  For 3D: 6 more launches.

Total launches per iteration (3D): approximately `8 + 3 + 6 = 17` kernel launches.  For 2D:
approximately `6 + 3 + 4 = 13`.

**Convergence check (epoch-last-step only, `fdm_torch.py:69-71`):**
```python
err = iarr_pad[core] - prev               # 1 kernel + slice
maxerr = torch.max(torch.abs(err))        # 2 kernels (abs + max)
if prec and maxerr < prec:                # ← implicit .item() → GPU sync
```

The Python `if` on a 0-dim CUDA tensor forces a **host↔device synchronisation** (equivalent
to `.item()`) at every epoch-last-step.  This is the only forced sync in the inner loop
(not per-step, but once per `epoch` steps).

**Clone for `prev` (`fdm_torch.py:61`):**
```python
prev = iarr_pad.clone().detach().requires_grad_(False)
```
Clones the **full padded array** (not just the core) — see also [04-memory-usage.md](04-memory-usage.md).
This is executed once per `epoch` steps.

**Summary (torch, per iteration):**
- ~17 CUDA kernel launches
- 0 host↔device syncs (except once per `epoch` steps for convergence check)
- 1 full-padded-array clone every `epoch` steps

### 2.4 fdm_cupy (GPU path)

Same stencil pattern as torch — `fdm_generic.stencil` is reused (`fdm_cupy.py:12`), so
the per-iteration kernel launch count is identical (~17 for 3D).

**Convergence check (`fdm_cupy.py:71-73`):**
```python
maxerr = cupy.max(cupy.abs(err))      # 2 kernels
if prec and maxerr < prec:            # ← cupy __bool__ syncs
```

Same forced sync once per `epoch` steps.

**Key difference from torch:** the clone is core-sized only:
```python
prev = cupy.array(iarr_pad[core])    # fdm_cupy.py:61  ← core only
```
This is smaller than the torch clone.

### 2.5 fdm_cumba (GPU path)

**Stencil:** a single `@cuda.jit` kernel launch per step (`fdm_cumba.py:32-48`).  This is
significantly better than the Python-loop approach: **1 kernel launch** for the stencil
instead of `2N + 2`.

**But:** the update (`fdm_cumba.py:82`) is:
```python
iarr_pad = bi_pad + mutable_pad * tmp_pad
```
This involves 2 cupy elementwise kernel launches plus it **allocates a new padded array** on
every step (see [C-3](02-potential-bugs.md)).

Edge condition and convergence check: same as torch/cupy.

**3D kernel is broken** (`fdm_cumba.py:24`): `cuda.grid(2)` unpacked into 3 variables —
see [B-A2](02-potential-bugs.md).  The cumba engine only works in 2D.

**Summary (cumba, per iteration, 2D only):**
- 1 CUDA stencil kernel launch
- ~3 cupy kernel launches for update
- ~4 kernel launches for edge condition
- 1 full-padded-array allocation per step (memory churn)
- 1 full-padded-array clone once per `epoch` steps

---

## 3. Cross-command GPU↔CPU↔disk round-trips

This is the **single largest efficiency issue** in the pipeline.

```
pochoir fdm (GPU) → .cpu() / .get() → numpy.savez → disk
                                           ↓ (new process)
pochoir velo       ← numpy.load ← disk
   numpy compute (gradient, mobility, velocity)
   → numpy.savez → disk
                                           ↓ (new process)
pochoir drift      ← numpy.load ← disk
   CPU compute (scipy solve_ivp / torchdiffeq on cpu)
   → numpy.savez → disk
                                           ↓ (new process)
pochoir srdot      ← numpy.load ← disk
   CPU compute (scipy RGI dot product)
   → numpy.savez → disk
```

For every pipeline command:
1. The full domain array (potential, gradient, velocity, paths) is read from disk into host
   memory.
2. All computation happens on the host (except FDM).
3. Results are written back to disk.

The GPU is loaded once per `pochoir fdm` invocation, does its work, and then unloads.
No data stays on the GPU between commands.

On a typical modern workstation with NVMe storage and a fast GPU, the FDM itself might take
seconds to minutes, but the disk round-trips for large grids (e.g. a 3D 1000³ float64 domain
= 8 GB) would dominate.

---

## 4. Inner-loop synchronisation summary

| Back-end | Sync point | Frequency | Type |
|----------|------------|-----------|------|
| torch | `if maxerr < prec:` (`fdm_torch.py:71`) | once per `epoch` steps | implicit `.item()` |
| torch | `torch.max(torch.abs(err))` (`fdm_torch.py:69`) | once per `epoch` steps | async (syncs at `if`) |
| cupy | `if maxerr < prec:` (`fdm_cupy.py:73`) | once per `epoch` steps | cupy `__bool__` sync |
| cumba | `if maxerr < prec:` (`fdm_cumba.py:89`) | once per `epoch` steps | cupy `__bool__` sync |
| torch drift | `print(...)` (`drift_torch.py:50`) | every ODE eval (~6×/tick) | stdout flush |
| all FDM | `print(f'epoch: ...')` (`fdm_numpy.py:54`) | once per epoch | stdout |

With the default `--epoch 1000`, the convergence sync fires once per 1000 steps, which is
acceptable.  However, if the user runs with `--epoch 1` (to check convergence every step),
there will be one GPU sync per iteration.

The `print` in `drift_torch.py:50` fires on every ODE function evaluation — with `dopri5`,
the adaptive integrator calls the RHS 6+ times per time tick.  For a typical drift of
~1000 time ticks and ~6 evaluations per tick, that is ~6000 `print` calls per path.  With
Python's print going to stdout (potentially line-buffered), this alone can dominate drift
runtime.

---

## 5. Parallelism opportunities not exploited

### 5.1 Drift: paths are integrated serially

`__main__.py:441-443`:

```python
for ind, point in enumerate(start_points):
    path = drifter(dom, point, velo, ticks, verbose=verbose)
    thepaths[ind] = path
```

P drift paths are computed one at a time, sequentially in Python.  For 1000 start points,
this means 1000 serial calls to `solve_ivp` or `odeint`, each building its own
`RegularGridInterpolator` objects from scratch inside `Simple.__init__`.

The `Simple` objects are constructed with the same `vfield` data each time — there is no
caching of the interpolators across paths.  On the numpy engine, building P sets of N
scipy RGIs from a potentially large velocity array is repeated P times.

If `drift_torch.py` were adapted to run on GPU, all P paths could potentially be integrated
in parallel (with a batched initial condition tensor of shape `(P, ndim)`).

### 5.2 Stencil: per-dimension Python loop instead of one fused kernel

The `fdm_generic.stencil` function (`fdm_generic.py:55-66`) executes `2N + 2` CUDA kernel
launches (for torch/cupy back-ends) where a single fused kernel could compute the same
result.  A fused kernel would:
- Reduce kernel-launch overhead (`2N + 2 → 1`).
- Improve L2-cache reuse (all 2N neighbours read in one pass).
- Potentially double throughput on memory-bandwidth-limited GPUs.

The `fdm_cumba.py` CUDA kernel (`fdm_cumba.py:13-29`) does provide a fused version, but
only for the stencil itself; the update and edge-condition remain Python-level cupy calls.

### 5.3 Gradient / velocity: no GPU path end-to-end

The `arrays.gradient` torch branch (`arrays.py:108-111`) explicitly round-trips through CPU:

```python
a = array.to('cpu').numpy()       # D2H copy
gvec = numpy.gradient(a, spacing)
g = numpy.array(gvec)
return to_torch(g, device=array.device)  # H2D copy
```

The comment at `arrays.py:104-107` acknowledges this is a known deficiency ("At the cost
of possible GPU→CPU→GPU transit, for now we do the dirty").  PyTorch ≥ 1.11 provides
`torch.gradient` which can compute finite-difference gradients on GPU tensors without
leaving the device.

For a 3D domain, the gradient computation involves `N=3` full-domain copies (see
[04-memory-usage.md](04-memory-usage.md)), and with the torch round-trip those copies pass
through PCI-e twice.

### 5.4 Velocity / mobility: `numpy.vectorize` on every grid point

`lar.mobility` (`lar.py:51`) uses `numpy.vectorize(mobility_function)`, which calls the
Python-level `mobility_function` once per element.  For a 3D domain with millions of cells,
this is millions of Python-level function calls.  A vectorised implementation using
`numpy` ufuncs or a torch tensor expression would be orders of magnitude faster.

### 5.5 ODE evaluation: per-dimension Python loop

`drift_torch.Simple.__call__` (`drift_torch.py:53-56`):

```python
for ind, inter in enumerate(self.interp):
    got = inter(point_as_list)
    velo[ind] = got
```

This is a Python loop over `ndim` (2 or 3) interpolator calls.  The same pattern appears in
`drift_numpy.Simple.interpolate` (`drift_numpy.py:47-55`).

For scipy RGI, multi-output evaluation is possible by stacking the value arrays, but the
current structure builds one interpolator per component and calls them individually.

---

## 6. Impact summary by stage

| Stage | GPU used? | Kernel efficiency | Sync overhead | Parallelism |
|-------|-----------|-------------------|---------------|-------------|
| FDM (torch) | Yes | Medium (2N+2 launches/step) | 1 sync per epoch | Single stencil |
| FDM (cupy) | Yes | Medium (same) | 1 sync per epoch | Single stencil |
| FDM (cumba 2D) | Yes | Better (1 launch/step) | 1 sync per epoch | Single stencil |
| FDM (cumba 3D) | Broken | N/A | N/A | N/A |
| velo | No | Poor (numpy.vectorize mobility) | N/A | None |
| grad | No | Medium (numpy.gradient) | N/A | None |
| drift (numpy) | No | Poor (1 path at a time) | N/A | None |
| drift (torch) | No (CPU) | Poor (per-step prints) | N/A | None |
| induce | No | Medium | N/A | None |
| srdot | No | Poor (nested Python loops) | N/A | None |

---

## 7. Notes on measurement

This document is based solely on code reading.  To get actual performance numbers, the
recommended next steps are:

1. **Profile FDM** with `torch.profiler` or `nvtx` ranges to measure actual kernel times
   and memory-bandwidth utilisation.
2. **Measure drift time** with `time.perf_counter` around the `for point in start_points`
   loop to see how much of total runtime is drift vs FDM.
3. **Disable the print in drift_torch** temporarily and re-time to isolate the print overhead.
4. **Compare numpy vs torch FDM** on the same problem to quantify the GPU speedup (accounting
   for H2D/D2H transfer time).
