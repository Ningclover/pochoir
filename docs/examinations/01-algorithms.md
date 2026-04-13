# 01 — Algorithm Walkthrough

This document explains what the `pochoir` code computes, in what order, and how each
back-end implements the core operations. Cross-references to [02-potential-bugs.md](02-potential-bugs.md)
are marked **[B-X]**.

---

## 1. Physics context

`pochoir` computes the electrical current induced on TPC readout electrodes when an ionisation
charge drifts through the detector volume.  The calculation follows the **Ramo–Shockley theorem**:
the instantaneous induced current on electrode `k` is

```
i_k(t) = q · E_k(r(t)) · v(r(t))
```

where `E_k` is the *weighting field* (gradient of the weighting potential solved with unit
voltage on electrode `k` and all others grounded), `v` is the drift velocity of the charge, and
`q` is the charge amount.

Two independent Laplace problems must be solved:

1. The **electric potential** produced by the realistic operating voltages, used to compute the
   drift velocity field.
2. The **weighting potential** of each electrode of interest, used to compute the induced
   current via the Ramo theorem.

In `pochoir`, both are solved by the same FDM engine; the difference is only in the boundary
conditions painted onto the grid.

---

## 2. Full pipeline

### 2.1 Command data-flow

```
pochoir domain            → stores grid metadata (shape, spacing, origin)
pochoir init / gen        → paints initial-value array (IVA) and boundary-value array (BVA)
pochoir fdm               → solves Laplace, stores scalar potential
pochoir velo              → gradient(V) → E-field → µ(|E|) → drift velocity
pochoir starts            → stores seed points for drift
pochoir drift             → integrates drift paths through the velocity field
pochoir induce            → dQ/dT from weighting potential interpolated on paths
    OR
pochoir srdot             → Ramo dot product  -q · E_w · v
pochoir convertfr         → formats output in Wire-Cell JSON schema
```

Each arrow represents one `pochoir` CLI invocation (a fresh Python process).  Data passes
through the store (NPZ directory or HDF5 file) between every step.  **No GPU state persists
across commands.**  See [03-gpu-efficiency.md § 1](03-gpu-efficiency.md) for why this matters.

### 2.2 2D → 3D lifting sub-flow

For a 3D problem whose boundary conditions come from a simpler 2D solution:

```
pochoir fdm (2D)          → 2D potential
pochoir bc-interp         → paints 2D result onto X-faces of a 3D IVA/BVA
pochoir fdm (3D)          → full 3D Laplace solution
pochoir extendwf          → extends weighting field across extra strips
```

---

## 3. Domain representation

`pochoir/domain.py:11` — The `Domain` class stores:

| Attribute | Meaning |
|-----------|---------|
| `shape` | Number of grid cells per axis (integer tuple) |
| `spacing` | Physical cell size per axis (float tuple) |
| `origin` | Physical coordinate of cell (0,0,0) (float tuple) |
| `bb` | Bounding box (2×N, derived from origin+shape×spacing) |
| `linspaces` | List of 1-D coordinate arrays for each axis |

The grid is **cell-centred**; `linspaces` returns `linspace(first, first+(num-1)*sp, num)`
(`domain.py:97`), so coordinates run from `origin` to `origin + (shape-1)*spacing` inclusive.

---

## 4. FDM (Laplace solver)

### 4.1 The Laplace problem

The code solves the discrete Laplace equation

```
∇²V = 0
```

on a rectangular N-D grid subject to Dirichlet boundary conditions (cells marked in the
boundary-value array `barr`).  The solution is the scalar potential `V`.

### 4.2 Stencil

Implemented in `fdm_generic.py:35-67`.

For an N-dimensional grid the **Jacobi stencil** averages the 2N nearest neighbours:

```
V_new[i,...] = (1 / 2N) * Σ_{dim=0}^{N-1} ( V[i+1,...] + V[i-1,...] )
```

In 2D this is `(V[i+1,j] + V[i-1,j] + V[i,j+1] + V[i,j-1]) / 4` and in 3D divided by 6.
This is a second-order finite-difference approximation to the Laplacian.

The function operates on a **padded** array (padded by 1 cell on each side) so that the shifted
views never go out of bounds.  It writes into the *core* region only (the inner region
excluding the 1-cell pad), which has shape `(s₀-2, s₁-2, …)`.

Key lines:
- `fdm_generic.py:35-67` — generic numpy/torch/cupy implementation via Python loops over dims.
- `fdm_numba.py:7-19` — `@numba.stencil` decorated version (`_lap2d`, `_lap3d`).
- `fdm_cumba.py:13-29` — `@cuda.jit` decorated version (`stencil_numba2d_jit`, `stencil_numba3d_jit`).

### 4.3 Boundary mask and update formula

Each engine maintains two pre-computed arrays:

| Array | Shape | Meaning |
|-------|-------|---------|
| `bi_core` | unpadded (=core shape) | `iarr × barr`: values of *fixed* cells, zero elsewhere |
| `mutable_core` | unpadded | `~barr`: True where cell is free to update |

One Jacobi iteration in `fdm_torch.py:63-64` (same logic in cupy/cumba):

```python
stencil(iarr_pad, tmp_core)            # average neighbours → tmp_core
iarr_pad[core] = bi_core + mutable_core * tmp_core
```

Interpretation: "keep the fixed boundary cells unchanged, replace all others with the stencil
average."  This is a Jacobi step — the new values are written from a scratch buffer `tmp_core`,
not in-place, so there is no read-write race on the same array.

In `fdm_numpy.py:62`, the numpy engine uses a slightly different style:

```python
set_core1(iarr, tmp, core)    # iarr[core] = tmp  (stencil result)
set_core2(iarr, fixed, ifixed) # iarr[ifixed] = fixed  (restore boundaries)
```

Functionally equivalent: first write the stencil result everywhere, then overwrite the boundary
cells with their fixed values.

### 4.4 Epoch / convergence loop

All five back-ends share the same loop structure (`fdm_numpy.py:53-74`, mirrored in others):

```python
for iepoch in range(nepochs):
    for istep in range(epoch):
        if epoch - istep == 1:          # last step of this epoch
            prev = copy(iarr[core])
        stencil(iarr_pad, tmp_core)
        update(iarr_pad)
        edge_condition(iarr_pad, *periodic)
        if epoch - istep == 1:          # last step — check convergence
            err = iarr_pad[core] - prev
            maxerr = max(|err|)
            if prec and maxerr < prec:
                return (solution, err)
```

- `epoch` — number of iterations between convergence checks.  The snapshot `prev` and the
  difference `err` are computed only on the **last step of each epoch block**, not every step.
  This means convergence is sampled at most once per `epoch` iterations.
- `nepochs` — hard ceiling on the total number of epochs.  Maximum total iterations = `epoch × nepochs`.
- `prec` — precision threshold.  If `max|err| < prec`, the solver exits early.

The CLI defaults are `--epoch 1000 --nepochs 1` (`__main__.py:283-285`), meaning the solver
runs 1000 iterations and checks convergence once.

**Edge condition** (`fdm_generic.py:3-32`) is applied after every step to refresh the 1-cell
ghost frame.  See §4.5.

### 4.5 Edge condition

`fdm_generic.py:3-32`.  For each dimension, either periodic or "fixed" treatment is applied to
the ghost cells (the outermost 1-cell pad).

**Periodic (`per=True`):**
```
ghost_left  = interior_right_neighbour   (wrap)
ghost_right = interior_left_neighbour    (wrap)
```
This implements a periodic Jacobi step: opposite edges see each other.

**"Fixed" (`per=False`):** ⚠ **See [B-B1] in [02-potential-bugs.md]**
```
ghost_left  = first_interior_cell         (mirror)
ghost_right = last_interior_cell          (mirror)
```
Despite being named "fixed", this implements a **zero-gradient (Neumann) mirror** condition,
not a Dirichlet fixed-value condition.  The name is misleading.  The Dirichlet boundary values
are managed separately via `bi_core`/`mutable_core` masks on the interior cells — the `edge_condition`
function handles only the *outer ghost frame*, which is only needed to give the stencil
valid neighbours for cells at the interior edge.

### 4.6 Back-end comparison

| Back-end | File | Stencil | Device | Notes |
|----------|------|---------|--------|-------|
| `numpy` | `fdm_numpy.py` | `fdm_generic.stencil` (Python loop) | CPU | Reference implementation. `module(arr)` dispatch means it also works with cupy arrays. |
| `numba` | `fdm_numba.py` | `@numba.stencil` (`_lap2d`, `_lap3d`) | CPU | JIT-compiled; calls `solve_numpy` with the numba stencil injected. Returns a full-size array then slices to core. |
| `torch` | `fdm_torch.py` | `fdm_generic.stencil` (Python loop, on GPU tensors) | GPU (`cuda:0`) or CPU | `tmp_core` allocated as float32; rest as float64. See **[B-A1]** (numpy.bool) and **[B-B2]** (dtype mismatch). |
| `cupy` | `fdm_cupy.py` | `fdm_generic.stencil` (Python loop, on cupy arrays) | GPU | Dead arrays (`barr_pad`, `ifixed`, `fixed`) waste GPU memory. Inconsistent return type on early exit. See **[B-C1]**. |
| `cumba` | `fdm_cumba.py` | `@cuda.jit` (`stencil_numba2d_jit`) | GPU | 2D kernel correct. **3D kernel broken** (see **[B-A2]**). Update rebinds `iarr_pad` each step. |

---

## 5. Gradient and velocity (`velo` command)

`__main__.py:345-360`.

```
potential  →  efield = gradient(V)  →  emag = |efield|  →  mu = mobility(emag, T)  →  varr = efield * mu
```

**Gradient** (`arrays.py:96-111`):

- Numpy path: `numpy.gradient(array, *spacing)` — uses central differences, second-order accurate.
  Returns a list of `ndim` component arrays (one per axis) stacked into a single `(ndim, *shape)` array.
- Torch path: bounces to CPU via `.to('cpu').numpy()`, calls `numpy.gradient(a, spacing)` (note: `spacing`
  not unpacked — see **[B-B3]**), then moves back to the original device.

`arrays.py:354`, `__main__.py:354`: **No minus sign**.  `efield = gradient(V)`, not `-gradient(V)`.
Whether this gives the correct physical drift direction depends on the sign convention of the stored
potential.  See **[B-B4]** for the open question.

**Mobility** (`lar.py:10-51`):

The `mobility_function` uses the parametrisation from [BNL LAr properties](https://lar.bnl.gov/properties/trans.html):

```
mu(E, T) = (a₀ + a₁E + a₂E^(3/2) + a₃E^(5/2)) / [(1 + (a₁/a₀)E + a₄E² + a₅E³) · (T/T₀)^(3/2)]
```

where `E` is in kV/cm and `T₀ = 89 K`.  Input field `Emag` is converted:
`Emag_kVcm = Emag / (kV/cm)` (`lar.py:19`), then the result in cm²/s/V is converted
back to system units (`lar.py:47-49`).

`mobility` is `numpy.vectorized` (`lar.py:51`), so it accepts arrays; however, it uses
`math.sqrt` internally (`lar.py:36-38`) which means it is called element-by-element in Python
for each grid point — not a vectorised NumPy ufunc call.

**Velocity** (`__main__.py:357`): `varr = [e * mu for e in efield]`.  `efield` is a list of
`ndim` arrays, each multiplied by `mu` (scalar-field array).  The result is a Python **list**,
stored as-is; `numpy.savez` will try to pack it as an object array or a stacked array depending
on shapes.

---

## 6. Drift paths (`drift` command)

`__main__.py:403-447`.

### 6.1 Loop structure

```python
for ind, point in enumerate(start_points):          # __main__.py:441
    path = drifter(dom, point, velo, ticks, ...)
    thepaths[ind] = path
```

Paths are computed **one at a time**, sequentially in Python.  There is no batching across
start points even when using the torch engine.  `ticks` is a 1-D array of evaluation times
built as `linspace(start, stop, nsteps, endpoint=False)` (`__main__.py:430`).

### 6.2 numpy engine (`drift_numpy.py`)

Uses `scipy.integrate.solve_ivp` with method `'Radau'` (implicit Runge–Kutta, stiff)
(`drift_numpy.py:91-95`), `rtol=atol=1e-4`.

`Simple.__call__(time, pos)` (`drift_numpy.py:61-77`) is the ODE right-hand side: it
interpolates the velocity field at `pos` using `scipy.interpolate.RegularGridInterpolator`
(one per velocity component) with `fill_value=0.0`.

Bounding-box check (`drift_numpy.py:39-43`): if the particle leaves the domain, `extrapolate`
returns `numpy.zeros_like(pos)`, freezing the path.

### 6.3 torch engine (`drift_torch.py`)

Uses `torchdiffeq.odeint` with method `'dopri5'` (adaptive Runge–Kutta, 4/5 order),
`rtol=atol=0.01` (`drift_torch.py:73`).

`Simple.__call__(tick, tpoint)` (`drift_torch.py:43-60`): loops over velocity components,
calls `torch_interpolations.RegularGridInterpolator` per component.  **Prints every ODE
evaluation** (`drift_torch.py:50`).

**Critical note:** `device = 'cpu'` is hard-coded at `drift_torch.py:67`.  Despite using
`torchdiffeq`, this engine **never touches the GPU**.  See **[C-1]** in
[03-gpu-efficiency.md](03-gpu-efficiency.md).

There is no `inside()` / bounds check.  Out-of-bounds evaluation returns whatever
`torch_interpolations.RegularGridInterpolator` extrapolates (see **[B-B6]**).

### 6.4 Grid-point construction issue

Both engines build the interpolation grid via `numpy.arange(start, stop, spacing)`.
`numpy.arange` with float step can return `n` or `n+1` points depending on floating-point
rounding (`drift_numpy.py:31`, `drift_torch.py:35`).  A debug `print` at `drift_numpy.py:32`
exists precisely because this mismatch has been observed.  See **[B-D2]** in
[02-potential-bugs.md](02-potential-bugs.md).

---

## 7. Induced current — two approaches

### 7.1 `induce` command (finite-difference dQ/dT)

`__main__.py:573-645`.

1. Load the **weighting potential** `wpot` (shape = domain) and build a
   `RegularGridInterpolator` on it (`__main__.py:609`).
2. Shift the drift paths along X by `shift_x = dom.shape[0]*dom.spacing[0]/2.0` to align
   them with the weighting-field coordinate system (`__main__.py:621`).
3. Evaluate `Q = charge * rgi(shifted_paths)` — the charge-weighted potential at each
   path point.  Shape: `(nstrips*npaths, nsteps)`.
4. Differentiate: `dQ = Q[:, 1:] - Q[:, :-1]`, `dT = ticks[1:] - ticks[:-1]`,
   `I = dQ / dT`.  Result has shape `(npaths, nsteps-1)`.

The time-series has length `nsteps-1` because it represents differences between adjacent
samples.

### 7.2 `srdot` command (Ramo dot product)

`__main__.py:720-749`, implementation in `srdot.py:6-42`.

1. Compute the **weighting E-field**: `sol_Ew = gradient(pot, dom_Ew.spacing)` (`__main__.py:739`).
   Note: `dom_Ew.spacing` is passed as a single list argument, not unpacked — see **[B-B3]**.
2. Build `RegularGridInterpolator` for each component of `E_w` and for each component of
   velocity (`srdot.py:22-23`).
3. For each point on each path:
   - Evaluate velocity `V` at the **un-shifted** point.
   - Shift the point: `point[0] += shift` (in-place mutation of the input array! — see **[B-B5]**).
   - Evaluate `E_w` at the shifted point.
   - Accumulate `i = q * dot(E_w, V)` with `q = -1` hard-coded (`srdot.py:26`).
4. Result is a Python list of lists `I[path][tick]`, length `nsteps` per path (not `nsteps-1`).

**Time-base mismatch:** `induce` produces length `nsteps-1`; `srdot` produces length `nsteps`.
The two outputs cannot be directly compared without resampling.

### 7.3 Sign convention (open question)

- `velo` computes `E = +∇V` and `v = µ·E`.
- `srdot` computes `E_w = +∇V_w` and `i = (-1)·(E_w·v)`.
- `induce` computes `i = dQ/dT = charge · d(V_w)/dt`.

The sign of the induced current depends on the sign convention of the stored potential.
Whether the `+∇V` convention is correct must be verified against the physics simulation or
a known analytic test case.  See **[B-B4]**.

---

## 8. 2D → 3D boundary-condition interpolation (`bc-interp`)

`bc_interp.py:8-44`, `__main__.py:450-490`.

1. **Tile** the 2D solution `sol2D` (shape `(Nx, Nz)`) into a 3D array `sol2D_ext`
   (shape `(Nx, Ny, Nz)`) by copying `sol2D` identically for every Y slice
   (`bc_interp.py:21-22`).  The 2D solution is treated as translation-invariant along Y.
2. Build a `RegularGridInterpolator` on `sol2D_ext`.
3. **Mark** the X=0 and X=-1 faces of the 3D boundary array as fixed:
   `barr3D[0,:,:] = 1`, `barr3D[-1,:,:] = 1` (`bc_interp.py:26-27`).
4. **Paint** those two faces of the 3D initial-value array with values sampled from the
   interpolated `sol2D_ext` at the appropriate X coordinates.

This is **Dirichlet-BC painting**, not a volumetric lift: only the two X-normal boundary
slabs receive values from the 2D solution.  The interior of the 3D domain is left as
initialised by `gen` / `init`, and a subsequent `fdm` invocation fills it by Laplace
relaxation.

---

## 9. Cross-reference table

| Pipeline step | File | Key function / line | Engine variants | On-disk hand-off |
|---------------|------|---------------------|-----------------|-----------------|
| Grid | `domain.py:11` | `Domain.__init__` | — | JSON metadata (attrs) |
| Paint BCs | `geom.py:21` | `init` | — | `iarr` (f32), `barr` (bool) |
| Laplace solve | `fdm_*.py` | `solve(iarr, barr, ...)` | numpy / numba / torch / cupy / cumba | `potential` (f64 or f32) |
| Gradient | `arrays.py:96` | `gradient(array, *spacing)` | numpy / torch→CPU | stacked `(ndim, *shape)` array |
| Mobility | `lar.py:10` | `mobility_function` | numpy.vectorize | (in-memory only) |
| Velocity | `__main__.py:357` | list comp `[e*mu for e in efield]` | — | list of `ndim` arrays |
| Starts | `__main__.py:399` | `starts` command | — | `(P, ndim)` array |
| Drift | `drift_*.py` | `solve(domain, start, velo, times)` | numpy (scipy) / torch (torchdiffeq, CPU) | `(P, T, ndim)` array |
| Induce | `__main__.py:587` | `induce` command | scipy RGI | `(P, T-1)` current |
| Ramo dot | `srdot.py:6` | `dotprod(...)` | scipy RGI | nested list `P×T` |
| BC lift | `bc_interp.py:8` | `interp(...)` | scipy RGI | updated `iarr3D`, `barr3D` |
