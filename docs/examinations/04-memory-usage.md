# 04 — Memory Usage and Savings Opportunities

This document inventories the GPU and CPU memory allocated at each pipeline stage, identifies
wasted or redundant allocations, and describes (read-only) opportunities to reduce peak usage.
All estimates use symbolic sizes; `N = prod(domain.shape)` (total unpadded grid cells),
`Np ≈ N·∏(1 + 2/shape_i)` (padded; approaches `N` for large grids).

---

## 1. Dtype audit

The dtype of the potential array propagates through the whole pipeline unless explicitly cast.

| Generator / initialiser | IVA dtype | Notes |
|------------------------|-----------|-------|
| `geom.init` (`geom.py:45`) | **float32** (`'f4'`) | Used by `init` command and `gen_sandh*` |
| `gen_sandh2d` (`gen_sandh2d.py:45`) | **float32** | Explicitly `"float32"` |
| `gen_pcb_quarter` (`gen_pcb_quarter.py:143`) | **float64** | `numpy.zeros` default |
| `gen_pcb_2Dstrips` (`gen_pcb_2Dstrips.py:61`) | **float64** | same |
| `gen_pcb_3Dstrips` (`gen_pcb_3Dstrips.py:56`) | **float64** | same |

PCB strip generators produce **float64** arrays.  For large 3D grids this doubles GPU memory
compared to float32.

**In `fdm_torch.py:47`:** regardless of the input dtype, `tmp_core` is allocated as
**float32** (PyTorch's default dtype):

```python
tmp_core = torch.zeros(iarr.shape, requires_grad=False).to(device)
```

`iarr_pad` is the input dtype (float64 for PCB generators).  The stencil accumulates into
`tmp_core` (float32), then the update promotes back to float64.  This is a dtype mismatch
that silently degrades stencil precision even though the potential array stays float64.
See also [B-B2](02-potential-bugs.md).

**In `drift_torch.py:68-70`:** all tensors are hard-cast to **float32**:

```python
start    = torch.tensor(start,    dtype=torch.float32, device=device)
velocity = [torch.tensor(v,        dtype=torch.float32, device=device) for v in velocity]
times    = torch.tensor(times,    dtype=torch.float32, device=device)
```

So even if the potential was computed in float64, drift integration always uses float32.
Over long drift paths this can accumulate positional error.

---

## 2. FDM engine memory inventory

In the tables below, `f64 = 8 bytes`, `f32 = 4 bytes`, `bool = 1 byte` per element.
"Live on GPU" means the tensor exists on the GPU device during the solver loop.

### 2.1 fdm_numpy

All allocations are on CPU host memory.

| Array | Shape | Dtype | Bytes | Notes |
|-------|-------|-------|-------|-------|
| `iarr` (padded) | `Np` | f64 | `8Np` | Working array |
| `barr` (padded) | `Np` | bool | `Np` | Boundary mask |
| `fixed` | `sum(barr)` | f64 | `≤8N` | Fixed-cell values |
| `err` | `N` | f64 | `8N` | Error array |
| `tmp` (per-step alloc) | `N` | f64 | `8N` | Stencil result, freed after each step |
| `prev` (per-epoch alloc) | `N` | f64 | `8N` | Snapshot, once per `epoch` steps |

**Peak (epoch-last-step):** `8Np + Np + 8N + 8N + 8N + 8N ≈ 40N` bytes.

---

### 2.2 fdm_torch

All tensors transferred to `cuda:0` (if available) via `.to(device)`.  Allocated once before
the loop except `prev`.

| Array | Shape | Dtype | Bytes on GPU | Notes |
|-------|-------|-------|-------------|-------|
| `bi_core` | `N` (unpadded) | f64¹ | `8N` | Fixed-cell values, pre-multiplied |
| `mutable_core` | `N` | bool | `N` | Free-cell mask |
| `tmp_core` | `N` | **f32** ← bug [B-B2] | `4N` | Stencil accumulator |
| `barr_pad` | `Np` | bool | `Np` | **Never used in loop — dead** |
| `iarr_pad` | `Np` | f64¹ | `8Np` | Working array |
| `prev` (epoch-last-step) | `Np` (full pad) | f64¹ | `8Np` | Cloned unnecessarily large |
| Temporaries in update | ~`N` | f64 | ~`8N` | `bi_core + mutable_core*tmp_core` expression |

¹ f64 assumes PCB generators; f32 for sandh generators.

**Peak GPU (epoch-last-step):**
`8N + N + 4N + Np + 8Np + 8Np + 8N ≈ 9N + 17Np`

For large grids where `Np ≈ N`: **~26N bytes on GPU** (float64) = **~26 × N × 8 bytes**.

Plus a CPU copy of the original `iarr` + `barr` (pre-transfer, not yet freed) ≈ `9N` bytes.

**Simultaneous tensors live on GPU at epoch-last-step:**
`bi_core`, `mutable_core`, `tmp_core`, `barr_pad`, `iarr_pad`, `prev` = 6 tensors.

---

### 2.3 fdm_cupy

| Array | Shape | Dtype | Bytes on GPU | Notes |
|-------|-------|-------|-------------|-------|
| `iarr` (device copy) | `N` | f64 | `8N` | Input transferred to GPU |
| `barr` (device copy) | `N` | bool | `N` | Boundary, transferred |
| `bi_core` | `N` | f64 | `8N` | Fixed values |
| `mutable_core` | `N` | bool | `N` | Free mask (`cupy.invert(barr)`) |
| `tmp_core` | `N` | f64 | `8N` | Stencil accumulator |
| `err` (initial) | `N` | f64 | `8N` | Immediately overwritten at first epoch-last-step |
| `barr_pad` | `Np` | bool | `Np` | **Dead — only used to compute ifixed/fixed** |
| `iarr_pad` | `Np` | f64 | `8Np` | Working array |
| `ifixed` | `Np` | bool | `Np` | **Dead — never used in loop** |
| `fixed` | `≤N` | f64 | `≤8N` | **Dead — never used in loop** |
| `prev` (epoch-last-step) | core ~`N` | f64 | `8N` | Core-sized clone (better than torch) |

**Dead GPU arrays:** `barr_pad` + `ifixed` + `fixed` = `Np + Np + ≤N` bytes ≈ `≤10N` bytes
of GPU memory pinned for the entire solve with no purpose.

**Peak GPU (epoch-last-step):**
`8N + N + 8N + N + 8N + 8N + Np + 8Np + Np + 8N + 8N ≈ 50N + 10Np` bytes.

For large grids: **~60N bytes on GPU** (float64).

---

### 2.4 fdm_cumba

| Array | Shape | Dtype | Bytes on GPU | Notes |
|-------|-------|-------|-------------|-------|
| `iarr_pad` | `Np` | f64 | `8Np` | Working array; **rebound every step** |
| `barr_pad` | `Np` | bool | `Np` | Padded boundary mask |
| `bi_pad` | `Np` | f64 | `8Np` | Fixed values, padded |
| `mutable_pad` | `Np` | bool | `Np` | Free mask, padded |
| `tmp_pad` | `Np` | f64 | `8Np` | Stencil output (kernel writes interior only) |
| `err` (initial) | `N` | f64 | `8N` | Unpadded; immediately orphaned |
| `prev` (epoch-last-step) | `Np` | f64 | `8Np` | Full-padded clone |
| Temporary from `bi_pad + mutable_pad*tmp_pad` | `Np` | f64 | `8Np` | Transient every step |

**Transient peak (epoch-last-step, during rebind at line 82):**
- Before assignment: `iarr_pad` (old), `bi_pad`, `mutable_pad*tmp_pad` (temp), `bi_pad+mutable_pad*tmp_pad` (new), `prev` simultaneously alive.
- That is `8Np + 8Np + 8Np + 8Np + 8Np = 40Np` ≈ **40N bytes** for float64 arrays.

**Steady-state (not at rebind step):**
`8Np + Np + 8Np + Np + 8Np + 8N ≈ 24Np + 8N ≈ 32N` bytes.

---

### 2.5 Engine comparison table

| Engine | Peak GPU memory | Peak CPU memory | Device |
|--------|----------------|----------------|--------|
| numpy | — | ~40N bytes | CPU only |
| numba | — | ~40N bytes | CPU only |
| torch | ~26N × 8 bytes (f64) | ~10N bytes (pre-transfer) | GPU |
| cupy | ~60N × 8 bytes (f64) | ~10N bytes (pre-transfer) | GPU |
| cumba | ~40N × 8 bytes (f64) | ~10N bytes (pre-transfer) | GPU |

For a 3D 500³ grid (N = 125,000,000 cells):
- Float64 per cell = 8 bytes → N = 1 GB.
- FDM torch peak: ~26 GB GPU.
- FDM cupy peak: ~60 GB GPU.
- FDM cumba transient peak: ~40 GB GPU.

---

## 3. Other command peak memory

### 3.1 `velo` command

`__main__.py:345-360`:

```python
efield = pochoir.arrays.gradient(pot, *dom.spacing)  # (ndim, *shape)
emag   = pochoir.arrays.vmag(efield)                 # (*shape)
mu     = pochoir.lar.mobility(emag, temp)            # (*shape)
varr   = [e*mu for e in efield]                      # list of ndim (*shape) arrays
```

Inside `arrays.gradient` (`arrays.py:102`):
```python
numpy.array(numpy.gradient(array, *spacing))
```
`numpy.gradient` returns a Python **list of ndim arrays**, each of shape `(*shape)`.
`numpy.array(...)` then stacks them into a new `(ndim, *shape)` array.  Both the list and
the stacked result exist simultaneously.

**Peak at gradient call:** `pot(N) + list of ndim×N + stacked ndim×N = (2·ndim + 1)·N`.

**Peak at velo end:** `pot(N) + efield(ndim·N) + emag(N) + mu(N) + varr(ndim·N) = (2·ndim + 2)·N`.

For 3D: **(8)·N float64 arrays** = 8×N×8 bytes.  For a 500³ grid: ~8 GB CPU peak.

No GPU is used.

### 3.2 `grad` command

Same gradient call: peak `(2·ndim + 1)·N` at the call, then `ndim·N` for the stored result.

### 3.3 `drift` command

Pre-allocated path array: `thepaths = zeros((P, T, ndim))` (`__main__.py:439`).

Inside each `drifter` call:
- numpy: scipy RGI holds a copy of each velocity component (`N` per component × `ndim`).
  These `ndim` RGIs are constructed per-call (no caching) so each call allocates `ndim·N`
  floats for the interpolation structures, then frees them.
- torch: `[torch.tensor(v, dtype=float32) for v in velocity]` creates `ndim` float32 copies
  of the velocity components (`4·ndim·N` bytes), held for the whole solve.

**Peak per path call (numpy engine):** `ndim·N` (RGI data) + path `T·ndim` (negligible).

**Across P paths (numpy engine):** at any one time only one path is in-flight, so the
path overhead is bounded by `ndim·N + T·ndim`.

### 3.4 `srdot` command

`srdot.py:22-23`:
```python
ew_interp  = [RGI(points_ew, ew_i)   for ew_i in pcb_3Dstrips_sol]   # ndim RGIs
velo_interp = [RGI(points_v, v_i)    for v_i in velo]                 # ndim RGIs
```

`pcb_3Dstrips_sol` = the stacked gradient, shape `(ndim, *shape_ew)`.
`velo` = the stacked velocity, shape `(ndim, *shape_v)`.

Both are held as RGI internal copies simultaneously.  Plus the input arrays.

**Peak:** `sol_Ew(ndim·N_ew) + sol_Drift(N_drift) + velo(ndim·N_v) + 2·ndim·N` (for the RGIs)
≈ `(4·ndim + 1)·N` float64.

For 3D: **~13·N** float64 = 13×N×8 bytes.  For a 500³ grid: ~13 GB CPU peak.

### 3.5 `induce` command

`__main__.py:573-645`:

- `wpot` (weighting potential): `N` floats.
- RGI over `wpot`: typically a second copy of `N` floats inside the scipy RGI.
- `shifted_paths`: a full copy of the path array, shape `(P, T, ndim)` or larger if
  `nstrips > 1`.  When `nstrips <= 1`, `numpy.array(shifted_paths)` (`__main__.py:623`)
  materialises this into a dense array.
- `Q`: shape `(P_total, T)` float64 from RGI evaluation.
- `dQ`, `dT`, `I_tot`: shape `(P_total, T-1)`.

**Peak:** `2·N + shifted_paths(P·T·ndim) + Q(P·T) + dQ(P·T) + dT(T) + I_tot(P·T)`.

For typical small `P` and `T`, the dominant term is `2·N` (potential + RGI copy).

---

## 4. Savings opportunities

These are observations only — no code changes are made in this review pass.  The savings
should be evaluated against the physics requirements (float32 accuracy, in-process pipeline
feasibility) before being implemented.

---

### S-1 · Drop `barr_pad` / `ifixed` / `fixed` in fdm_cupy

`fdm_cupy.py:47-52` allocates `barr_pad` (`Np` bool), `ifixed` (`Np` bool), and `fixed`
(up to `N` float64) on the GPU.  None are used in the update loop.  Removing these three
lines saves up to `2Np + N ≈ 3N` bytes of GPU memory with no change in results.

### S-2 · Drop unused `barr_pad` in fdm_torch

`fdm_torch.py:49`:
```python
barr_pad = torch.tensor(numpy.pad(barr, 1), requires_grad=False).to(device)
```
`barr_pad` is never read after creation.  Removing it saves `Np` bool bytes = `Np` bytes on GPU.

### S-3 · Clone `prev` on core only (not full padded array) in fdm_torch

`fdm_torch.py:61`:
```python
prev = iarr_pad.clone().detach().requires_grad_(False)   # clones Np elements
```

Only `iarr_pad[core]` is read at line 68 (`err = iarr_pad[core] - prev[core]`).  Cloning
the core only:
```
prev = iarr_pad[core].clone()    # clones N elements
```
would save approximately `(Np - N) ≈ 2·N/shape_per_dim` elements per clone.  For a
1000³ 3D grid with 1-cell padding, `Np - N ≈ 3×10⁶` elements = 24 MB per clone (float64).

### S-4 · Clone `prev` on core only in fdm_cumba

`fdm_cumba.py:78`:
```python
prev = cupy.array(iarr_pad)    # full Np clone
```
Same as S-3: only `iarr_pad[core]` and `prev[core]` are compared at line 86.  A core-only
clone saves the ghost-frame overhead.

### S-5 · Replace `iarr_pad = bi_pad + mutable_pad*tmp_pad` with in-place ops in fdm_cumba

`fdm_cumba.py:82`:
```python
iarr_pad = bi_pad + mutable_pad * tmp_pad
```
This rebinds `iarr_pad` to a new allocation every iteration.  An in-place equivalent:
```
iarr_pad[:] = bi_pad + mutable_pad * tmp_pad
```
or with `cupy.multiply` and `cupy.add` in-place would avoid the transient double-peak.
The transient saves `8Np ≈ 8N` bytes GPU at every step.

### S-6 · Use float32 globally to halve GPU memory

All PCB generators produce float64 arrays.  The Laplace equation is solved to a precision
of `prec` (CLI default `0.0`, meaning full `epoch × nepochs` iterations), but the physically
relevant precision for field-response calculations is typically `~10⁻⁴` in potential, which
is within float32 range (`~10⁻⁷` relative precision for float32).

Switching to float32 globally would:
- Halve GPU memory for FDM (from ~26N×8 to ~26N×4 bytes for torch).
- Double the number of grid cells that fit in a given GPU memory budget.
- Potentially double memory bandwidth throughput (GPU memory bandwidth is often the bottleneck
  for stencil operations).

This requires verifying that float32 precision is sufficient for the specific physics use case.

### S-7 · Fix `tmp_core` dtype in fdm_torch to avoid float32 accumulation

`fdm_torch.py:47`:
```python
tmp_core = torch.zeros(iarr.shape, requires_grad=False).to(device)
```
Change to match `iarr_pad.dtype`:
```python
tmp_core = torch.zeros(iarr.shape, dtype=iarr_pad.dtype, ...).to(device)
```
(Note: `iarr_pad` must be created before `tmp_core` for this to work, or infer dtype from
the numpy input.)  This prevents the silent float32 accumulation issue described in
[B-B2](02-potential-bugs.md) at no additional memory cost.

### S-8 · Use `torch.gradient` for the GPU gradient (avoid round-trip)

`arrays.gradient` torch branch (`arrays.py:108-111`) moves data CPU→GPU→CPU→GPU:

```python
a = array.to('cpu').numpy()
gvec = numpy.gradient(a, spacing)
g = numpy.array(gvec)
return to_torch(g, device=array.device)
```

PyTorch ≥ 1.11 provides `torch.gradient(input, spacing=..., dim=...)` which computes
finite differences entirely on the device.  This would:
- Eliminate the two full PCI-e transfers (D2H + H2D) of the potential array.
- Keep the gradient computation in GPU memory, enabling an end-to-end on-device
  `fdm → gradient → velocity → drift` pipeline without disk round-trips (if drift is also
  brought to the GPU).

### S-9 · Cache RGI objects across drift paths

In `drift_numpy.py:16-37` (inside `solve`), `Simple.__init__` constructs `ndim`
`RegularGridInterpolator` objects from the full velocity field on every call.  Since the
same `vfield` is used for every start point, the RGIs could be built once and reused across
all P paths.  This would eliminate P-1 redundant RGI constructions, each of which may
involve copying the velocity data into the RGI's internal structure.

### S-10 · Architectural: keep GPU state across CLI commands

The most impactful memory and performance improvement would be to run the full pipeline
`fdm → velo → drift → srdot` in a single Python process, keeping the potential and velocity
tensors on the GPU throughout.  This avoids:
- 4 full disk writes of domain-sized arrays.
- 4 full disk reads.
- Multiple D2H/H2D transfers.

The current CLI-per-command architecture was designed for flexibility (restart, inspect
intermediate results), but an optional `--pipeline` or in-process runner mode could
provide the end-to-end GPU path for production runs.

---

## 5. Unanswered quantitative questions

Before prioritising any of the savings opportunities above, the following numbers should
be measured or decided:

| Question | Why it matters |
|----------|---------------|
| Typical domain size in production? | Determines absolute memory in GB; some savings (S-3/S-4) are tiny for small grids |
| Is float32 sufficient for physics? | Determines whether S-6/S-7 can be applied |
| How many paths P are typical? | Determines whether serial drift loop or RGI caching (S-9) is the bottleneck |
| What fraction of runtime is FDM vs drift vs induced-current? | Determines where optimisation effort is best spent |
| Which GPU is available and how much VRAM? | Determines feasibility of cupy vs torch, and of S-10 |
| Is disk I/O a bottleneck between commands? | If yes, S-10 has the highest payoff |
