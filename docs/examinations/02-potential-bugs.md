# 02 — Potential Bugs

Bugs are grouped by category from most to least severe. Each entry gives: the exact
`file:line`, what the code does today, why it is suspicious or incorrect, and a suggested
way to verify.

---

## Category A — Import / Crash bugs

These will crash at import time or at first call on common modern-library versions.

---

### A-1 · `numpy.bool` removed in NumPy ≥ 1.24

**File:** `fdm_torch.py:46`

```python
mutable_core = torch.tensor(numpy.invert(barr.astype(numpy.bool)), requires_grad=False).to(device)
```

`numpy.bool` was deprecated in NumPy 1.20 and removed in NumPy 1.24 (released December 2022).
On any modern NumPy installation this raises:

```
AttributeError: module 'numpy' has no attribute 'bool'
```

This line is executed every time `fdm --engine torch` is invoked, so the torch FDM engine
is completely non-functional on current NumPy.

The intended operation is `~barr` (bitwise NOT on a bool array), equivalent to
`numpy.invert(barr.astype(bool))` with the built-in Python `bool`.

**Verification:** `python3 -c "import numpy; numpy.bool"` — will raise on NumPy ≥ 1.24.

---

### A-2 · 3D CUDA kernel unpacks `cuda.grid(2)` into three variables

**File:** `fdm_cumba.py:24`

```python
@cuda.jit
def stencil_numba3d_jit(arr, out):
    i, j, k = cuda.grid(2)     # ← 3-variable unpack from a 2-tuple
```

`cuda.grid(ndim)` returns an `ndim`-tuple.  With argument `2` it returns two values `(i, j)`.
Attempting to unpack those two values into `i, j, k` will raise a `ValueError` at kernel
launch time:

```
ValueError: not enough values to unpack (expected 3, got 2)
```

As a result, the `cumba` engine only works for **2D problems**.  Any 3D problem using
`--engine cumba` crashes.

The fix requires changing `cuda.grid(2)` to `cuda.grid(3)` and adjusting the grid/block
dimensions accordingly (the 2D launch config at `fdm_cumba.py:43-48` also needs to be
updated for 3D).

**Verification:** Invoke `pochoir fdm --engine cumba` on any 3D domain.

---

### A-3 · `persist.py` uses `numpy` without importing it

**File:** `persist.py:71, 88`

```python
# persist.py:71
if isinstance(obj, numpy.ndarray):   # NameError: name 'numpy' is not defined
# persist.py:88
return numpy.asarray(obj)            # same
```

`numpy` is not in `persist.py`'s namespace — only `hdf`, `npz`, `schema`, and `json`
are imported (`persist.py:1-10`).  This breaks `persist.todict` and `persist.fromdict`,
which are called from `persist.dumps` / `persist.dumpfr`.

The affected CLI command is `convertfr` (`__main__.py:647-718`), which calls
`persist.dumpfr(output, fr)` at line 718.  Running `pochoir convertfr ...` will crash with
`NameError` at the `todict` step.

**Verification:** `python3 -c "from pochoir import persist; persist.todict({})"`.

---

### A-4 · `persist.py` uses `mkstemp` without importing it

**File:** `persist.py:42`

```python
from tempfile import mkdtemp    # only mkdtemp is imported (persist.py:36)
...
fd, tmp = mkstemp(suffix=".hdf")  # NameError: name 'mkstemp' is not defined
```

The `tempstore` context manager for the HDF5 backend will raise `NameError` at line 42.
The NPZ branch is unaffected.

**Verification:** Run any command that uses a temporary HDF5 store.

---

### A-5 · `npz.Store.close` references `self.fp` which is never set

**File:** `npz.py` (`close` method)

```python
def close(self):
    self.fp.close()    # AttributeError: 'Store' object has no attribute 'fp'
```

`npz.Store.__init__` creates `self.basedir` and `self.mode` but never sets `self.fp`.
`close()` is never called in the normal code path (`main.py` does not call it), but any
user code that calls `.close()` on an NPZ store will raise `AttributeError`.

---

### A-6 · `click.exit` does not exist

**File:** `__main__.py:559, 563`

```python
click.exit(-1)    # AttributeError: module 'click' has no attribute 'exit'
```

The `move_paths` command (`__main__.py:542-569`) calls `click.exit(-1)` for both its
error-exit paths (missing taxon, wrong taxon).  `click` has no `exit` function; the intended
call is `sys.exit(-1)`.  As written, the error handler itself will crash with `AttributeError`
instead of exiting cleanly.

---

### A-7 · `arrays.dup` passes unsupported kwarg to `torch.clone`

**File:** `arrays.py:132`

```python
def dup(array):
    if is_torch(array):
        import torch
        return torch.clone(array, requires_grad=False)   # TypeError in modern torch
```

`torch.clone` has the signature `torch.clone(input, *, memory_format=...)`.  It does not
accept a `requires_grad` keyword argument.  This will raise `TypeError` on any modern
PyTorch.  The correct idiom is `array.detach().clone()` or `array.clone().detach()`.

`dup` is used in `fdm_numpy.py:58` (as `amod.array(...)`) only on the numpy path, so the
torch-code path of `dup` may not yet have been exercised.

---

## Category B — Numerical / Algorithm correctness

---

### B-1 · `edge_condition` "fixed" branch implements Neumann mirror, not Dirichlet

**File:** `fdm_generic.py:21-32`

```python
else:                   # "fixed"
    arr[tuple(dst1)] = arr[tuple(src2)]   # ghost_left  = first_interior
    arr[tuple(dst2)] = arr[tuple(src1)]   # ghost_right = last_interior
```

The label `# fixed` and the CLI option `"fixed"` (`__main__.py:280`) suggest a Dirichlet
(constant-value) condition.  But the code copies the **first interior cell into the left ghost**
and the **last interior cell into the right ghost**.  This is a **zero-normal-gradient (Neumann
mirror)** boundary, not a Dirichlet boundary.

The actual Dirichlet conditions for the physical boundary electrodes are handled separately
via `bi_core`/`mutable_core` masks on cells explicitly marked in `barr`.  The `edge_condition`
function manages only the outer ghost frame used by the stencil.  So if a user's domain has
Dirichlet boundaries only on interior cells (well within the grid), the "fixed" ghost condition
is merely unused and has no effect.  But if a user intends to use `--edges fixed` to enforce a
Dirichlet condition on the domain boundary faces themselves (e.g. ground planes at the domain
edge), they will get Neumann behaviour instead.

The test suite (`test/test_fdm.py`) should include a case with a known analytical solution
on a Dirichlet boundary to confirm whether the current behaviour is intentional.

See also [01-algorithms.md § 4.5](01-algorithms.md) for the algorithm context.

---

### B-2 · `fdm_torch.py:47` — `tmp_core` is float32 while `iarr_pad` is float64

**File:** `fdm_torch.py:47`

```python
tmp_core = torch.zeros(iarr.shape, requires_grad=False).to(device)
```

`torch.zeros` uses PyTorch's default dtype, which is **float32**.  However, `iarr_pad` is
constructed by:

```python
iarr_pad = torch.tensor(numpy.pad(iarr, 1), requires_grad=False).to(device)
```

`torch.tensor` infers the dtype from the numpy array.  Since `iarr` comes from generators
like `gen_pcb_*` that use `numpy.zeros` (default float64), `iarr_pad` is **float64**.

The stencil result is written into `tmp_core` (float32) via the generic `fdm_generic.stencil`,
then the update:

```python
iarr_pad[core] = bi_core + mutable_core * tmp_core
```

`mutable_core * tmp_core` promotes to float64 (the higher type), and the whole expression is
float64.  But the stencil accumulation inside `fdm_generic.stencil` (`res += array[...]`) uses
`res` (= `tmp_core`, float32) as the accumulator, so intermediate sums are computed in float32
and then implicitly upcast to float64 at assignment.  This silently reduces the precision of
each Jacobi step while storing the final value at float64 width.

The practical effect is that the torch engine solves a slightly different (noisier) problem
than the numpy engine, even though the arrays look the same dtype at the end of each step.

See [04-memory-usage.md § 2](04-memory-usage.md) for the memory implications.

---

### B-3 · `arrays.gradient` torch branch does not unpack `spacing`

**File:** `arrays.py:109`

```python
a = array.to('cpu').numpy()
gvec = numpy.gradient(a, spacing)          # ← spacing is a tuple/list, not unpacked
g = numpy.array(gvec)
```

The numpy branch (same function, line 102) correctly uses `*spacing`:

```python
return numpy.array(numpy.gradient(array, *spacing))   # correct
```

`numpy.gradient(a, spacing_list)` interprets the single positional argument as a coordinate
array for the **first axis** only, not as per-axis spacings.  For a 3D array of shape
`(Nx, Ny, Nz)` with `spacing = (dx, dy, dz)`, numpy receives a 3-element list and interprets
it as 3 coordinate values along axis 0.  Since `len(spacing) = 3 ≠ Nx`, numpy raises a shape
mismatch error.

The same bug appears at `__main__.py:739` in the `srdot` command:

```python
sol_Ew = pochoir.arrays.gradient(pot, dom_Ew.spacing)    # ← not unpacked
```

This is consistent with the torch-path bug above and will silently mis-compute the
weighting E-field for the Ramo calculation.  Compare with the correct usage at
`__main__.py:354` and `:377` where `*dom.spacing` is properly unpacked.

**Verification:** Compare `gradient(arr, 1.0, 1.0, 1.0)` vs `gradient(arr, [1.0, 1.0, 1.0])`
on a known 3D field.

---

### B-4 · Sign of E-field (`E = +∇V` vs `E = -∇V`) — open physics question

**File:** `__main__.py:354`, `srdot.py:38`

```python
efield = pochoir.arrays.gradient(pot, *dom.spacing)   # no minus sign
```

The physical electric field is `E = -∇V`.  The code uses `+∇V`.

This may be intentional if the potential `pot` is defined with the opposite sign convention
(i.e., if the generator paints boundary values with the opposite sign), but this is not
documented anywhere in the code.  The `srdot` command uses `q = -1` hard-coded (`srdot.py:26`)
and then `i = q * dot(E_w, V)`, so there are two sign flips (from `q` and from the missed
minus in `E_w`) whose net effect depends on whether they cancel.

**This is not asserted here to be a bug** — it may be correct by convention.  But the
convention should be verified against a known test case (e.g. two parallel plates at known
potentials with known drift direction).

---

### B-5 · `srdot.dotprod` mutates the caller's path array in-place

**File:** `srdot.py:34-36`

```python
shift = pcb_3Dstrips_domain.shape[0]*pcb_3Dstrips_domain.spacing[0]/2.0
point[0] = point[0] + shift      # ← in-place assignment on a view into pcb_drift
```

`pcb_drift` is a numpy array of shape `(P, T, 3)`.  The loop variable `point` at
`srdot.py:31` is a **view** (row) of this array, not a copy.  The in-place `point[0] = ...`
permanently modifies the original path data.

Consequences:
1. After `srdot.dotprod` returns, the caller's `pcb_drift` has been corrupted — the X
   coordinate of every path point has been shifted.
2. Calling `srdot.dotprod` a second time on the same array will **double the shift**.
3. Any subsequent use of `pcb_drift` (e.g. visualisation, a second Ramo calculation for a
   different electrode) will use the wrong coordinates.

Note also that velocity `V` is evaluated at the **pre-shift** point (line 33) while the
weighting field `E_w` is evaluated at the **post-shift** point (line 37).  Whether this
coordinate offset between the drift domain and the weighting domain is intentional is not
documented.

---

### B-6 · `drift_torch.py` — no out-of-bounds / inside() check

**File:** `drift_torch.py:43-60`

The torch drift engine's `Simple.__call__` method has no bounds check.  When a path leaves
the grid, `torch_interpolations.RegularGridInterpolator` is called with an out-of-domain
point and returns an extrapolated value.  The path continues to "drift" at whatever speed the
extrapolation produces.

Compare with the numpy engine (`drift_numpy.py:67-72`), which explicitly checks
`self.inside(pos)` and returns `numpy.zeros_like(pos)` for out-of-bounds points, effectively
freezing the path.

Neither approach raises a warning to the user.  The `induce` and `srdot` commands then
evaluate the weighting potential at these potentially nonsensical out-of-domain coordinates.

---

### B-7 · `drift_numpy.py` out-of-bounds path is frozen but not flagged

**File:** `drift_numpy.py:58-71`

Once a path leaves the domain, velocity becomes zero and the path stays frozen in place for
all remaining time steps.  The returned path array has no flag or indicator that the point
left the domain.  The `induce` command will then evaluate the weighting potential at a fixed
point for the remainder of the time series, contributing a misleading constant value to `dQ`
(which will become zero after the first frozen step, but the path itself is still used).

---

### B-8 · `drift_numpy.py` constructor print on `arange` mismatch

**File:** `drift_numpy.py:32`

```python
print ("interp dim:", dim, rang.shape, vfield[dim].shape)
```

This debug print exists to detect a shape mismatch between the `numpy.arange` grid and
the velocity component array.  `numpy.arange` with floating-point arguments can produce
either `n` or `n+1` elements due to rounding, giving a different number of grid points
than the stored velocity array dimension.  The `RegularGridInterpolator` constructor will
raise a `ValueError` if the shapes are incompatible.

The print suggests the author encountered this problem but did not fix the root cause (using
`numpy.linspace(start, stop, n)` instead of `numpy.arange(start, stop, step)` would be
deterministic).  The same fragile pattern exists in `drift_torch.py:35`,
`srdot.py:13`, `bc_interp.py:14-16`, and `pathfinder.py:20`.

---

## Category C — Engine-specific logic bugs

---

### C-1 · `fdm_cupy.py` — dead GPU memory: `barr_pad`, `ifixed`, `fixed`

**File:** `fdm_cupy.py:47-52`

```python
barr_pad = cupy.pad(barr, 1)
iarr_pad = cupy.pad(iarr, 1)

# Get indices of fixed boundary values and values themselves
ifixed = barr_pad == True
fixed = iarr_pad[ifixed]
core = arrays.core_slices1(iarr_pad)
```

`ifixed` and `fixed` are computed here.  In the numpy engine (`fdm_numpy.py:48-49, 62`),
`fixed` is used in `set_core2(iarr, fixed, ifixed)` to restore Dirichlet cells after each
stencil step.  But in the cupy engine, the inner loop uses the `bi_core + mutable_core*tmp_core`
update (`fdm_cupy.py:65`), which does not use `ifixed` or `fixed`.  They are allocated on the
GPU and never read.

`barr_pad` is also allocated (`fdm_cupy.py:47`) but is only used to compute `ifixed`.  Since
`ifixed` is unused, `barr_pad` is effectively dead memory too.

See [04-memory-usage.md](04-memory-usage.md) for the memory waste estimate.

---

### C-2 · `fdm_cupy.py` — inconsistent return type between early and normal exit

**File:** `fdm_cupy.py:75, 78-79`

```python
# early exit (precision reached):
return (iarr_pad[core], err)            # returns cupy arrays on GPU

# normal exit (epoch limit reached):
res = (iarr_pad[core], err)
return tuple([r.get() for r in res])    # returns numpy arrays on CPU
```

The caller (`__main__.py:325-326`) receives either cupy arrays or numpy arrays depending on
which exit path was taken.  Then `ctx.obj.put(potential, arr, ...)` → `numpy.savez(...)` will
fail on cupy arrays (no implicit `.get()`).  In practice, the early-exit path may not have been
tested if precision was never reached in runs to date.

---

### C-3 · `fdm_cumba.py` — `iarr_pad` rebound to a new array every iteration

**File:** `fdm_cumba.py:82`

```python
iarr_pad = bi_pad + mutable_pad * tmp_pad
```

This is not an in-place update.  It creates a **brand-new cupy array** of size `Np` (padded
domain) on every single iteration step.  The old `iarr_pad` is released to the cupy allocator
only when it is no longer referenced, which happens one step later.  At the instant of this
line, both the old `iarr_pad` (still referenced by `core`, which is a slice tuple — no
reference to the data) and the new `iarr_pad` exist simultaneously, temporarily doubling
peak GPU memory for this tensor.

Combined with `prev = cupy.array(iarr_pad)` at line 78 (which clones the full padded array),
the epoch-last-step transiently holds **three** padded-size float64 arrays simultaneously:
`bi_pad + mutable_pad*tmp_pad` intermediate, the new `iarr_pad`, and `prev`.

See [04-memory-usage.md § 2.4](04-memory-usage.md) for the memory calculation.

---

### C-4 · `fdm_cumba.py` — `err` allocated with unpadded shape, compared with padded array

**File:** `fdm_cumba.py:66, 86`

```python
err = cupy.zeros_like(iarr)         # shape = iarr.shape (unpadded)
...
err = iarr_pad - prev               # shape = iarr_pad.shape (padded)
```

On the first epoch-last-step, `err` is rebound to `iarr_pad - prev`, which has the full
padded shape.  The initial allocation at line 66 is immediately orphaned and the returned
`err[core]` slice at line 91 is used instead.  Functionally OK (the initial zeros are
discarded), but the initial allocation wastes GPU memory until the first epoch-last-step.

---

### C-5 · `drift_torch.py` — device hard-coded to CPU

**File:** `drift_torch.py:67`

```python
device = 'cpu'
```

The torch drift engine uses `torchdiffeq.odeint`, which supports GPU tensors.  However, the
device is unconditionally set to `'cpu'`.  All tensors are created on CPU, and the final
`res.cpu().numpy()` at line 75 is a no-op (the tensor is already on CPU).

This means the "torch" drift engine provides **no GPU acceleration** over the numpy engine.
The only differences are the ODE solver (dopri5 vs Radau), the looser tolerances (`rtol=atol=0.01`
vs `1e-4`), and the interpolation library (`torch_interpolations` vs scipy).

See [03-gpu-efficiency.md § 2](03-gpu-efficiency.md) for the GPU utilisation audit.

---

### C-6 · `drift.py` — dead imports of `solve_numpyold` and `solve_scipy`

**File:** `drift.py:13-21`

```python
try:
    from .drift_numpyold import solve as solve_numpyold
except ImportError as err:
    ...
try:
    from .pathfinder import solve as solve_scipy
except ImportError as err:
    ...
```

The `drift` CLI command at `__main__.py:412` restricts engine choice to `["numpy", "torch"]`.
Neither `numpyold` nor `scipy` can be selected from the CLI.  `drift_numpyold.py` is an older
implementation using `scipy.integrate.odeint` instead of `solve_ivp`.  Both `solve_numpyold`
and `solve_scipy` are unreachable dead code from the CLI.

---

## Category D — Hard-coded assumptions and fragile code

---

### D-1 · `extendwf` hard-codes domain spacing and origin

**File:** `__main__.py:534`

```python
dom = pochoir.domain.Domain(arr.shape, 0.1, [0.0, 0.0, 0.0])
```

The output domain for `extendwf` is always constructed with `spacing=0.1` and `origin=(0,0,0)`
regardless of the input domain's spacing or origin.  Comments in the surrounding code
(`__main__.py:509, 518-519`) acknowledge this is not yet properly handled.  Any pipeline
that uses a different grid spacing will silently produce incorrect coordinates.

---

### D-2 · `arange`-based grid construction is fragile

**Files:** `drift_numpy.py:31`, `drift_torch.py:35`, `srdot.py:13`, `bc_interp.py:14-16`

All these locations use `numpy.arange(start, stop, spacing)` to build axis coordinate arrays
for `RegularGridInterpolator`.  `numpy.arange` with float step is non-deterministic in the
number of output points due to floating-point accumulation, potentially producing `n` or `n+1`
points.  The debug print at `drift_numpy.py:32` is a symptom of this being encountered in
practice.

Using `numpy.linspace(start, start + (n-1)*spacing, n)` (where `n` is known from the domain
shape) would be deterministic.

---

### D-3 · `gencfg.py` — `os.path.join` with absolute path silently drops `outdir`

**File:** `gencfg.py:58` (approximate)

```python
open(os.path.join(outdir, path), "wb")
```

If `path` is already absolute (as it will be after `assure_parent` resolves it), Python's
`os.path.join` silently discards `outdir`.  This accidentally works because `assure_parent`
already includes `outdir` in the resolved path, but the logic is fragile and confusing.

---

### D-4 · `arrays.is_cupy` relies on private CuPy symbol

**File:** `arrays.py:31`

```python
return isinstance(arr, cupy._core.core.ndarray)
```

`cupy._core.core.ndarray` is a private class.  In CuPy ≥ 11, the public class is
`cupy.ndarray`.  Relying on a private name risks `AttributeError` on future CuPy upgrades,
causing `is_cupy` to return `False` for all cupy arrays and `module()` to return `None`,
silently crashing on any subsequent `mod.zeros(...)` call.

---

### D-5 · `__main__.py:800` — `doma` undefined in `plot_scatter3d`

**File:** `__main__.py:800`

```python
dom = ctx.obj.get_domain(doma)   # NameError: name 'doma' is not defined
```

`doma` is referenced but never defined in the scope of `plot_scatter3d`.  This code path is
only reached when the array metadata does not contain a `"domain"` key, so it may not have
been triggered in practice.

---

### D-6 · `__main__.py:926` — `gif` undefined in `plot_drift`

**File:** `__main__.py:926`

```python
pochoir.plots.drift3d(arr, output, dom, trajectory, gif)   # NameError: name 'gif' is not defined
```

The `plot_drift` command (`__main__.py:904-928`) does not define or receive a `gif`
parameter, but it is referenced in the 3D branch.  This will raise `NameError` at runtime
when a 3D drift path is plotted.

---

### D-7 · `gen_sandh2d.py` — `isw` shadowed inside loop

**File:** `gen_sandh2d.py:35, 68`

```python
isw = any(p.get("weighting") for p in planes)  # outer flag
...
for plane in planes:
    isw = plane['weighting']                    # shadows the outer variable
    ...
if not isw:                                     # checks last plane's flag, not 'any'
    ...
```

The outer `isw` (line 35) checks whether *any* plane is a weighting plane.  Inside the
`for` loop (line 68), `isw` is reassigned to the current plane's `"weighting"` value.
After the loop, the `if not isw:` check at line 104 uses the *last* plane's weighting flag,
not the "any" flag.  For a multi-plane config where only the first plane is a weighting plane,
this produces incorrect behaviour.

---

### D-8 · `Main.get_domain` mutates metadata dict

**File:** `main.py:67-81`

```python
_, md = self.get(key, True)
shape = md.pop("shape")
spacing = md.pop("spacing")
```

`md.pop` removes keys from the dict returned by `self.get`.  For the HDF5 backend,
`hdf.Store.get` returns `ds.attrs` which is an h5py `AttributeManager` — a live view into
the HDF5 file.  Calling `.pop` on it may modify the on-disk attributes (h5py's behaviour on
attribute deletion).  For the NPZ backend, `get` returns a freshly parsed dict each call, so
`.pop` is safe but wastes the dict.  The HDF5 case is a potential data-corruption bug if
`get_domain` is called on an open HDF5 store.

---

### D-9 · `induce` comment-disabled assertion reveals silent mismatch

**File:** `__main__.py:626`

```python
#assert Q.shape[0] == npaths
```

This assertion was disabled, presumably because `Q.shape[0]` no longer equals `npaths` after
the multi-strip path expansion at lines 613-618 (where `nstrips * len(the_paths)` paths are
generated).  Leaving it commented out means the path-count mismatch is silently tolerated,
making it easy for callers to misinterpret the shape of the output current array.

---

## Appendix — Latent bugs outside the core FR pipeline

These bugs are in support code that does not directly affect the FDM/drift/Ramo calculation,
but will cause crashes in other workflows.

| File:line | Issue |
|-----------|-------|
| `persist.py:36,42` | `mkdtemp` imported, `mkstemp` used — `NameError` in HDF5 `tempstore` |
| `npz.py` (`close`) | `self.fp` never set — `AttributeError` on `close()` |
| `gen_pcb_quarter.py:4-5` | `matplotlib` imported but never used |
| `gen_pcb_3Dstrips.py:4-5` | same unused `matplotlib` import |
| `fdm_torch.py:7` | `import torch.nn as nn` — imported but never used |
| `fdm_cupy.py:7` | `from pochoir.fdm_numpy import solve as solve_numpy` — imported but unused |
| `fdm_cumba.py:53` | same unused `solve_numpy` import |
| `arrays.py:74` | `array.to('cpu').numpy()` — no `.detach()`, will crash if `requires_grad=True` |
| `arrays.py:120` | `vmag` uses `numpy.zeros_like` unconditionally — fails if input is torch tensor |
| `__main__.py:559,563` | `click.exit(-1)` — `AttributeError` (should be `sys.exit(-1)`) |
