# Algorithm: FDM Solver, Gradient, and Drift

---

## 1. Problem statement

Solve Laplace's equation on a regular N-D grid with uniform spacing h:

```
∇²V = 0    inside the domain
V   = Vᵢ  on Dirichlet boundaries (electrodes)
```

The solution V is the electrostatic potential. The electric field is
then E = −∇V. Drift paths are found by integrating

```
dr/dt = μ(|E|, T) · E
```

where μ is the electron mobility in liquid argon.

---

## 2. FDM discretisation — the stencil

On a uniform grid with spacing h, the second-order finite-difference
approximation of ∇²V at interior point i is:

```
∇²V ≈ (1/h²) · Σ_dim [ V(i + ê_dim) + V(i − ê_dim) − 2V(i) ] = 0
```

Rearranging: the value at i equals the arithmetic mean of its 2N
neighbours (N = number of dimensions):

```
V(i) = (1 / 2N) · Σ_{2N neighbours} V(neighbour)
```

This is the **Jacobi averaging step** — the stencil used by all backends.

In `pochoir`:
- **2D (5-point stencil):** weight = 1/4 per neighbour.
  - Generic: `fdm_generic.stencil()` at `fdm_generic.py:46–66`
  - Numba-CUDA kernel: `stencil_numba2d_jit` at `fdm_cumba.py:14–20`
- **3D (7-point stencil):** weight = 1/6 per neighbour.
  - Generic: same `fdm_generic.stencil()` (dimension-agnostic)
  - Numba-CUDA kernel: `stencil_numba3d_jit` at `fdm_cumba.py:23–29`

The generic stencil (`fdm_generic.py:35–67`) accumulates contributions
along each axis as array slices then multiplies by `1/(2*ndim)`.

---

## 3. Jacobi iteration

All backends implement **Jacobi iteration** (not Gauss-Seidel, not SOR):

1. Compute `tmp = stencil(iarr_pad)` — reads all neighbours from the
   current state into a *separate buffer*.
2. Write back: `iarr_pad[core] = bi_core + mutable_core * tmp`
   - `bi_core` holds the Dirichlet fixed values (zero elsewhere).
   - `mutable_core` is `True` where the cell is free (not a boundary).
   - This single expression simultaneously updates free cells with the
     stencil result *and* re-stamps Dirichlet values at fixed cells.
3. Refresh ghost layer via `edge_condition`.

Because `tmp` is computed *before* any writes (step 1 fully separates
from step 2), there are **no write-during-read races** — this is
textbook Jacobi and is numerically safe.

**Key point:** `pochoir` does **not** use SOR, red-black Gauss-Seidel,
or multigrid. Jacobi converges as O(1/N²) iterations for a grid of
side N, which is substantially slower than optimal methods. For a
100 × 100 × 2000 grid the effective convergence is dominated by the
longest dimension (2000 cells), so O(4 × 10⁶) iterations may be needed.

---

## 4. Boundary conditions

### 4a. Dirichlet (electrode) BCs

Before the solve loop, two arrays are derived:

```python
bi_core = iarr * barr        # fixed values (zero at free cells)
mutable_core = ~barr         # True where free, False where fixed
```

These are kept alive throughout the solve and re-applied every
iteration via the masked assignment in step 2 above.

Cite: `fdm_torch.py:44–45`, `fdm_cupy.py:41–42`, `fdm_cumba.py:63–64`.

### 4b. Ghost layer (outer boundary) — `edge_condition`

The working array `iarr_pad` is padded by one cell on every face
(`numpy.pad(iarr, 1)`, zero fill). After each stencil step,
`edge_condition` (`fdm_generic.py:3–32`) refreshes these ghost cells:

```
Periodic:    arr[0] ← arr[n-2]    (wrap from opposite interior)
             arr[n-1] ← arr[1]

Non-periodic: arr[0] ← arr[1]     (Neumann / zero-gradient reflect)
              arr[n-1] ← arr[n-2]
```

**Note:** despite the comment "fixed" in `fdm_generic.py:30`,
non-periodic edges do **not** enforce a fixed Dirichlet value — they
impose a **zero-gradient (Neumann) condition** on the ghost cell.
Dirichlet conditions at the true domain boundary must be encoded in
`barr` and `iarr`. See `02_bugs.md` for a discussion of the impact.

---

## 5. Convergence criterion

All backends check convergence **once per epoch** (every `epoch` steps,
default ≈ 100). The metric is the **L∞ change** between the state
`check_interval` iterations ago and the current state:

```
err = iarr_pad[core] − prev
maxerr = max(|err|)
```

Convergence is declared when `maxerr < threshold`. The threshold is
`prec` in the cupy and cumba backends, but `prec * check_interval`
(i.e. 100×) in the torch backend — an inconsistency documented in
`02_bugs.md`.

**Important caveat:** this metric measures the *change* in the
solution over the last `check_interval` iterations, not the true
*residual* (i.e. how far the current V is from satisfying ∇²V = 0).
For well-conditioned problems on this grid size they are closely
related, but convergence in change does not guarantee convergence in
residual.

---

## 6. Per-iteration sequence (cumba backend, the production path)

```
for each iteration:
    tmp_pad[:] = 0                    # reset output buffer
    stencil_numba3d_jit<<<G,B>>>      # custom CUDA kernel, 7-pt, reads iarr_pad, writes tmp_pad
    iarr_pad[:] = bi_pad + mutable_pad * tmp_pad   # update all cells (incl. halo, then clobbered)
    edge_condition(iarr_pad, ...)     # refresh halo: periodic or Neumann

every check_interval iterations:
    prev = iarr_pad[core].copy()

every epoch:
    err = iarr_pad[core] - prev
    if max(|err|) < prec: return
```

---

## 7. 2D + 3D splice workflow (production)

The full workflow runs **two separate FDM solves** and splices them:

### Step 1 — 2D solve

Solve the Laplace equation on a 2D slice (X × Z), capturing the full
drift length (Z ≈ 2000 voxels) but only the transverse X extent of the
geometry. This is cheap (2D) but lacks the Y (depth) structure.

### Step 2 — 3D solve near strips/pixels

Solve on a localised 3D sub-domain (X × Y × Z, where Z is truncated)
that captures the near-electrode 3D field. The 3D boundary conditions
along the outer X faces are derived from the 2D solution via `bc-interp`.

### Step 3 — bc-interp (`bc_interp.py:interp()`)

`bc_interp.interp(sol2D, arr3D, barr3D, dom2D, dom3D, xcoord)`:

1. Extrudes `sol2D` into a 3D volume `sol2D_ext` of shape
   `(dom2D.shape[0], dom3D.shape[1], dom2D.shape[1])` by replicating
   along the Y axis (`bc_interp.py:22–25`).
2. Builds a `scipy.interpolate.RegularGridInterpolator` over
   `sol2D_ext` (`bc_interp.py:27`).
3. Evaluates the interpolator at two X-boundary planes of the 3D domain
   — at `x = center ± xcoord` — and writes the result into
   `arr3D[0,:,:]` and `arr3D[-1,:,:]` (`bc_interp.py:43–44`).
4. Sets `barr3D[0,:,:] = 1` and `barr3D[-1,:,:] = 1` (marks those
   faces as Dirichlet boundaries) (`bc_interp.py:29–30`).
5. Also sets the far-Z face: `arr3D[:,j,-1] = sol2D[dom3D.shape[0]:
   dom3D.shape[0]*2, 1100]` — a **hard-coded Z-index of 1100** into
   sol2D (`bc_interp.py:48`).

### Step 4 — extendwf (`__main__.py:extendwf()`)

After both solves exist, `extendwf` stitches `sol2D` and `sol3D_full`
into a single full-volume weighting potential `arr` of shape
`(newXdim, dom3D.shape[1], dom2D.shape[1])`:

```
X bands:
  i < onestrip*7  (≈ 0–100):   arr[i,j,:] = sol2D[i,:]
  onestrip*7 ≤ i < onestrip*14: arr[i,j,:cut_z] = sol3D[i-100,j,:cut_z]
                                 arr[i,j,cut_z:] = sol2D[i,cut_z:]
  i ≥ onestrip*14:              arr[i,j,:] = sol2D[i,:]
```

where `onestrip = dom3D.shape[0] / 7.0` and `cut_z = 1100` are
**hard-coded** (`__main__.py:643, 646`).

Geometrically: the near-electrode 3D solution is used for the central
X strip band and for the first `cut_z` voxels in Z (near-electrode
region). Beyond `cut_z` in Z (the bulk drift region) the 2D solution
is used since the transverse field structure becomes negligible there.

See `02_bugs.md` for correctness concerns with the hard-coded constants
and the new domain spacing being set to a fixed value.

---

## 8. Gradient and electric field

After the solve, `__main__.velo` computes the electric field at
`__main__.py:362`:

```python
efield = pochoir.arrays.gradient(pot, *dom.spacing)
```

This calls `arrays.gradient()` (`arrays.py:96–111`), which uses
`numpy.gradient` — **central finite differences** with non-uniform
spacing support. The result is a stacked `(3, Nx, Ny, Nz)` array.

For a numpy potential (the normal path), this is a pure CPU operation.
For a torch potential (unusual), there is a GPU→CPU→GPU round-trip.

---

## 9. Drift integration

### 9a. Radau IVP (`drift_numpy.solve`)

```
solve_ivp(func, [t0, t_end], start,
          method='Radau', rtol=1e-10, atol=1e-10, t_eval=times)
```

- Uses an implicit Radau IIA scheme — unconditionally stable, suitable
  for stiff problems. For a smooth velocity field this is overly cautious.
- Tolerance `1e-10` is very tight (production-quality accuracy) but can
  make the solver extremely slow for a Python RHS (`drift_numpy.py:106–111`).
- The RHS interpolates from a `scipy.RegularGridInterpolator` at each
  evaluation, which involves Python-level dispatch.

### 9b. dopri5 ODE (`drift_torch.solve`)

```
odeint(func, start, times, rtol=0.01, atol=0.01)
```

- Uses adaptive Runge-Kutta (Dormand-Prince) from `torchdiffeq`.
- Tolerance `0.01` is loose — fast but less accurate than Radau.
- Currently forced to CPU (`drift_torch.py:67`, see `02_bugs.md`).

### 9c. Euler-Maruyama SDE (`drift_numpy.solve_sde`)

Explicit Euler-Maruyama with anisotropic diffusion:

```python
delta_pos = v_drift * dt_time                  # deterministic step
noise = sqrt(2*dt*D_L)*z_par*u + sqrt(2*dt*D_T)*z_perp   # stochastic
pos = pos + delta_pos + noise
```

- Correct covariance structure: `D_L` along the drift direction,
  `D_T` in the transverse plane (`drift_numpy.py:201–213`).
- Step size comes from `numpy.diff(times)` — chosen by the caller.
- No adaptive step size; fixed time array `times` must be supplied.
