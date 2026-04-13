# Potential Bugs and Correctness Issues

All citations are file:line in the repository source.
Severity levels: **Blocker** (produces wrong results silently),
**High** (crashes or gross behavioural error), **Medium** (edge cases,
performance regression, or latent breakage), **Low** (dead code,
misleading comments, minor fragility).

---

## FDM Backends

---

### BUG-01 — `fdm_torch` runs entirely on CPU
- **File:** `fdm_torch.py:44–49`
- **Severity:** Blocker
- **Description:** Every tensor in the torch backend is created without
  a `device=` argument, so all computation runs on CPU:
  ```python
  bi_core = torch.tensor(iarr*barr, requires_grad=False)
  mutable_core = torch.tensor(numpy.invert(barr.astype(bool)), ...)
  tmp_core = torch.zeros(iarr.shape, requires_grad=False)
  barr_pad = torch.tensor(numpy.pad(barr, 1), ...)
  iarr_pad = torch.tensor(numpy.pad(iarr, 1), ...)
  ```
  The "torch GPU backend" label is therefore misleading — it provides
  no GPU speedup over NumPy.
- **Fix hint:** Pass `device=torch.device('cuda')` (or a configurable
  device string) to all `torch.tensor()` and `torch.zeros()` calls.

---

### BUG-02 — Precision gate in `fdm_torch` is 100× looser than in cupy/cumba
- **File:** `fdm_torch.py:78`
- **Severity:** Blocker
- **Description:**
  ```python
  if prec and maxerr < prec * check_interval:   # fdm_torch
  if prec and maxerr < prec:                    # fdm_cupy:73, fdm_cumba:107
  ```
  `check_interval = 100`. So `fdm_torch` converges when the 100-iteration
  L∞ change is below `100 × prec`, not `prec`. At the same `prec` value,
  `fdm_torch` will stop ~100× earlier (coarser) than `fdm_cupy` /
  `fdm_cumba`. Results from the two backends are not comparable.
- **Fix hint:** Remove `* check_interval` from the torch comparison (or
  unify the comparison logic across all three backends).

---

### BUG-03 — `fdm_cupy` measures error over 1 iteration, not 100
- **File:** `fdm_cupy.py:60–70`
- **Severity:** Blocker
- **Description:** The numpy reference and torch/cumba backends use a
  `check_interval = 100` look-back: `prev` is sampled 100 steps before
  the end of the epoch and `maxerr` measures 100-step change. But `fdm_cupy`
  captures `prev` on the *penultimate* step (`epoch-istep == 1`, line 60)
  and computes `err` one step later (line 70), so `maxerr` is a
  *single-step* change:
  ```python
  # fdm_cupy.py:60
  if epoch-istep == 1:          # one step before end
      prev = cupy.array(iarr_pad[core])
  ...
  if epoch-istep == 1:          # same condition, next iter body
      err = iarr_pad[core] - prev   # diff over ONE step
  ```
  A run with `prec=1e-6` in cupy will be approximately 100× stricter
  than the same `prec` in cumba.
- **Fix hint:** Align cupy with the cumba/torch pattern (`check_interval
  = 100`, sample 100 steps before epoch end).

---

### BUG-04 — `fdm_cumba` writes BC update across the full padded volume (including halo)
- **File:** `fdm_cumba.py:96`
- **Severity:** Medium
- **Description:**
  ```python
  iarr_pad[:] = bi_pad + mutable_pad*tmp_pad   # writes entire padded array
  edge_condition(iarr_pad, *periodic)           # immediately overwrites halo
  ```
  `torch` and `cupy` write only `iarr_pad[core]` (the interior), leaving
  the halo untouched until `edge_condition`. Here, `bi_pad` and
  `mutable_pad` are padded with zeros (`numpy.pad` zero-fill), so on the
  halo: `0 + False * 0 = 0` — the halo is zeroed, then overwritten by
  `edge_condition`. The result is numerically correct because
  `edge_condition` runs immediately after, but it wastes global memory
  bandwidth writing a full padded volume just to discard the halo.
- **Fix hint:** Change to `iarr_pad[core] = bi_pad[core] + mutable_pad[core] * tmp_pad[core]`
  (matching torch/cupy style) or keep `[:]` but remove the duplicate
  halo writes.

---

### BUG-05 — Coalesced memory access is reversed in `fdm_cumba` kernels
- **File:** `fdm_cumba.py:14–29, 36–50`
- **Severity:** Medium (performance)
- **Description:** CUDA warp threads increment `threadIdx.x` fastest.
  `numba.cuda.grid(3)` returns `(i, j, k)` where `i ← threadIdx.x`,
  `j ← threadIdx.y`, `k ← threadIdx.z`. But for a row-major 3D array
  of shape `(l, n, m)`, the contiguous axis is `k` (stride = 1).
  Therefore warp threads increment `i` (stride = `n*m`), meaning
  consecutive threads access addresses that are `n*m = 200,000` elements
  apart — completely uncoalesced.

  The 3D block is `(8, 8, 16)` with thread-linear order
  `idx = tx + 8*ty + 64*tz`. For the first warp (32 threads):
  `tx = 0..7` drives `i`, so each of the first 8 threads accesses
  row `i = 0..7` of the same `(j, k)` location: stride `n*m` apart.

  The comment on line 43 says *"Z dimension gets more threads since
  it's the largest (2100)"* but only sets `threadsperblock[2]=16` for
  `k` — this is correct for occupancy but does not fix coalescing since
  `threadIdx.x` still drives `i`.

- **Measured impact (estimate):** A 7-point 3D stencil is memory-bound.
  Worst-case non-coalesced access can reduce effective bandwidth by 8–32×
  on NVIDIA GPUs. For 100×100×2000 × fp64, this may dominate total
  runtime.
- **Fix hint:** Swap axis mapping so that the fastest thread dimension
  (`threadIdx.x`) indexes the contiguous array axis (`k`):
  ```python
  k, j, i = cuda.grid(3)    # swap order
  threadsperblock = (32, 8, 4)   # or (16, 8, 8), BX*BY*BZ <= 1024
  ```

---

### BUG-06 — Dead code: `ifixed`/`fixed` in `fdm_cupy`
- **File:** `fdm_cupy.py:51–52`
- **Severity:** Low
- **Description:**
  ```python
  ifixed = barr_pad == True    # boolean mask on device
  fixed  = iarr_pad[ifixed]   # values — never used
  ```
  These are computed but never referenced. This is left-over code from
  the numpy reference backend's `set_core2(iarr, fixed, ifixed)` pattern.
- **Fix hint:** Delete lines 51–52.

---

### BUG-07 — `NameError` in `fdm_cupy` final print when error was never measured
- **File:** `fdm_cupy.py:77`
- **Severity:** Medium
- **Description:**
  ```python
  print(f'fdm reach max epoch ... last prec {prec} < {maxerr}')
  ```
  `maxerr` is only bound inside the `if epoch-istep == 1:` block
  (line 71). If `epoch == 1`, the block runs on the last step of every
  epoch — fine. But if `epoch == 0`, the inner loop never executes and
  `maxerr` is unbound; the print raises `NameError`. Also, if `nepochs`
  is reached before any epoch's `prev is not None` branch is entered
  (only possible if `epoch < 1`), same issue.
- **Fix hint:** Guard the print with `if prev is not None:` or
  initialise `maxerr = float('inf')` before the loop.

---

### BUG-08 — Silent dtype promotion in `fdm_cupy` and `fdm_cumba`
- **File:** `fdm_cupy.py:43`, `fdm_cumba.py:65`
- **Severity:** Medium
- **Description:**
  ```python
  tmp_core = cupy.zeros(iarr.shape)   # fdm_cupy.py:43
  tmp_pad  = cupy.zeros_like(iarr_pad) # fdm_cumba.py:65 — actually OK, inherits dtype
  ```
  `cupy.zeros(shape)` without a `dtype` argument defaults to **float64**.
  If the caller passed a float32 `iarr`, the masked update
  `bi_core + mutable_core * tmp_core` upcasts the result to float64,
  silently doubling memory traffic. (Note: the user has confirmed fp64
  is required, so this is currently harmless, but it makes the code
  behaviour unpredictable if fp32 is ever tried.)

  In `fdm_cumba.py` the stencil kernel computes `1/4.0` and `1/6.0`
  which are Python float (float64) literals. If `arr` is float32, the
  element-wise ops in the kernel promote to float64 on some GPUs.
- **Fix hint:** Propagate dtype: `cupy.zeros(iarr.shape, dtype=iarr.dtype)`.

---

### BUG-09 — `edge_condition` "fixed" is actually Neumann, not Dirichlet
- **File:** `fdm_generic.py:30–32`
- **Severity:** Medium (correctness landmine)
- **Description:**
  ```python
  else:   # comment says "fixed"
      arr[tuple(dst1)] = arr[tuple(src2)]  # arr[0] ← arr[1]
      arr[tuple(dst2)] = arr[tuple(src1)]  # arr[n-1] ← arr[n-2]
  ```
  This copies the adjacent *interior* cell into the ghost cell — a
  **zero-gradient (Neumann)** boundary, not a fixed Dirichlet value.
  Any user expecting a fixed potential value at the outer ghost layer
  (e.g. a ground plane beyond the padded domain) will silently get a
  different boundary condition.

  In current usage, all Dirichlet boundaries are encoded via `barr`
  and re-applied every iteration, so this is likely working as
  intended. But the misleading comment can lead to incorrect future
  modifications.
- **Fix hint:** Rename the `else` comment to `# Neumann: zero gradient`.

---

### BUG-10 — `maxerr` can be unbound in `fdm_numpy` final print
- **File:** `fdm_numpy.py:73`
- **Severity:** Low
- **Description:** Same pattern as BUG-07. `maxerr` is only bound inside
  `if epoch-istep == 1:`. If `nepochs=0` the loop never executes and
  the final print crashes.

---

### BUG-11 — Duplicated `set_core1`/`set_core2`
- **File:** `fdm_numpy.py:11–15`, `fdm_torch.py:13–17`
- **Severity:** Low
- **Description:** Both functions have the same body `dst[core] = src`.
  `set_core1` is called with a slice + ndarray (line 61 numpy, removed
  in torch/cupy/cumba which do inline assignment). `set_core2` is called
  with a boolean mask + flat vector (line 62). They work by numpy
  broadcast rules, but the naming implies different semantics that do
  not exist.

---

## `arrays.py` bugs

---

### BUG-12 — `arrays.gradient` missing `*` unpack for torch path
- **File:** `arrays.py:109`
- **Severity:** Blocker (wrong gradient values for torch inputs)
- **Description:**
  ```python
  # numpy path (line 102) — CORRECT:
  return numpy.array(numpy.gradient(array, *spacing))
  
  # torch path (line 109) — WRONG:
  gvec = numpy.gradient(a, spacing)   # spacing passed as a tuple, not unpacked
  ```
  `numpy.gradient(a, *spacing)` passes each axis's spacing scalar as a
  separate positional argument. `numpy.gradient(a, spacing)` with
  `spacing = (dx, dy, dz)` passes the *tuple* as a single argument,
  which numpy interprets as a 1-D coordinate array for the first axis
  only — numpy will raise a shape-mismatch error or silently compute
  a different result for multi-element spacing tuples.

  This also means that every call to `arrays.gradient` on a torch tensor
  incurs a full GPU→CPU→numpy→CPU→GPU round-trip (`arrays.py:108–111`),
  with a wrong result.
- **Fix hint:**
  ```python
  gvec = numpy.gradient(a, *spacing)   # unpack
  ```

---

### BUG-13 — `arrays.dup` passes `requires_grad=False` to `torch.clone`
- **File:** `arrays.py:131–132`
- **Severity:** High
- **Description:**
  ```python
  return torch.clone(array, requires_grad=False)  # invalid kwarg
  ```
  `torch.clone` does not accept `requires_grad`. This raises
  `TypeError: clone() got an unexpected keyword argument 'requires_grad'`
  at runtime. The function is likely never called on a torch tensor in
  current workflows, which is why the bug is undetected.
- **Fix hint:**
  ```python
  return array.clone().detach()
  ```

---

### BUG-14 — `arrays.vmag` uses `numpy.zeros_like` on a torch tensor
- **File:** `arrays.py:120`
- **Severity:** Medium
- **Description:**
  ```python
  c2s = [c*c for c in vfield]
  tot = numpy.zeros_like(c2s[0])   # will be a numpy array even if c2s[0] is torch
  for c2 in c2s:
      tot += c2                    # adds torch tensor to numpy array
  ```
  If `vfield` contains torch tensors, `c2s[0]` is a torch tensor,
  `numpy.zeros_like(c2s[0])` returns a numpy array (not a torch tensor),
  and the subsequent `tot += c2` mixes types, likely silently converting
  or raising at runtime.
- **Fix hint:** Use `arrays.module(c2s[0]).zeros_like(c2s[0])`.

---

### BUG-15 — `arrays.to_torch` always goes through CPU
- **File:** `arrays.py:83–84`
- **Severity:** Medium (performance)
- **Description:**
  ```python
  return torch.tensor(array, device=device)
  ```
  `torch.tensor()` always copies through CPU host memory. If `array`
  is a CuPy or existing CUDA tensor, this forces D→H→D. The correct
  path for same-device conversion is `torch.as_tensor` (for numpy) or
  `torch.from_dlpack` (for cupy).

---

## 2D/3D splice bugs

---

### BUG-16 — Hard-coded `cut_z = 1100` in `extendwf`
- **File:** `__main__.py:643`
- **Severity:** Blocker (for other geometries), Medium (current geometry)
- **Description:**
  ```python
  cut_z = 1100  # this is the number we cut 3Dweight sim along drift
  # NEEDS FIX for better calculation
  ```
  The splice Z-plane is not computed from `dom2D.shape[1]` or
  `dom3D.shape[2]`; it is a literal integer. If the domain geometry
  changes (different drift length, different voxel count), this silently
  produces wrong results. The self-comment `"NEEDS FIX"` acknowledges
  the issue. The same magic number `1100` appears again in `bc_interp.py:48`.

---

### BUG-17 — Hard-coded `onestrip = dom3D.shape[0] / 7.0` in `extendwf`
- **File:** `__main__.py:646`
- **Severity:** Medium
- **Description:**
  ```python
  onestrip = dom3D.shape[0]/7.0
  ```
  The 7-strip assumption is baked in. For the current 100-voxel X extent,
  `onestrip ≈ 14.28` and `onestrip*7 = 100.0`. The middle-band condition
  `onestrip*7 <= i < onestrip*14` only activates when `sol2D.shape[0] > 100`.
  If the geometry changes, the strip count changes, or if `dom3D.shape[0]`
  is not divisible by 7, the band boundaries will be off.

---

### BUG-18 — `extendwf` new domain uses hard-coded spacing 0.1 and origin [0,0,0]
- **File:** `__main__.py:676`
- **Severity:** Blocker (for non-standard spacing)
- **Description:**
  ```python
  dom = pochoir.domain.Domain(arr.shape, 0.1, [0.0, 0.0, 0.0])
  ```
  The spliced volume's domain is built with spacing `0.1` and origin
  `(0,0,0)` regardless of the actual spacings of `dom2D` and `dom3D`.
  If either input domain uses a different voxel spacing or a non-zero
  origin, all downstream `velo` and `drift` computations will use the
  wrong E-field scaling and absolute positions.

---

### BUG-19 — `bc_interp` sets boundary face with hard-coded slice into `sol2D`
- **File:** `bc_interp.py:48`
- **Severity:** Medium
- **Description:**
  ```python
  arr3D[:,j,-1] = sol2D[dom3D.shape[0]:dom3D.shape[0]*2, 1100]
  ```
  The far-Z face of the 3D initial array is set to a column of `sol2D`
  at Z-index 1100, which is the same hard-coded value as `cut_z` in
  `extendwf`. If `dom3D.shape[0] = 100`, this reads `sol2D[100:200, 1100]`.
  Correctness depends on `sol2D.shape[0] >= 200` and on 1100 being
  a meaningful Z position in the 2D domain.

---

### BUG-20 — `bc_interp.interp` modifies `barr3D` in-place (side effect)
- **File:** `bc_interp.py:29–30, 49`
- **Severity:** Medium
- **Description:**
  ```python
  barr3D[0,:,:]  = 1     # mutates caller's array
  barr3D[-1,:,:] = 1
  barr3D[:,:,-1] = 1
  ```
  The function is documented as "interpolate 2D solution into 3D
  boundary condition" but it also permanently mutates `barr3D`. If the
  caller keeps a reference to `barr3D` expecting the original mask to
  be preserved, this will corrupt it. The return value is `(arr3D,
  barr3D)` but the caller's `barr3D` variable already points to the
  mutated array, so the change is invisible — which makes it harder
  to detect.

---

## Drift bugs

---

### BUG-21 — `drift_torch.solve` hardcodes `device = 'cpu'`
- **File:** `drift_torch.py:67`
- **Severity:** Blocker
- **Description:**
  ```python
  device = 'cpu'
  start    = torch.tensor(start,    dtype=torch.float32, device=device)
  velocity = [torch.tensor(v, ...,  device=device) for v in velocity]
  times    = torch.tensor(times, ...,device=device)
  ```
  The drift tracer labelled "torch" runs entirely on CPU. No GPU
  acceleration is provided.

---

### BUG-22 — `drift_torch.Simple.__call__` prints tensor repr on every RHS call
- **File:** `drift_torch.py:50`
- **Severity:** High (performance)
- **Description:**
  ```python
  print(f'drift: point={tpoint} tick={tick}')
  ```
  Printing a tensor forces `__repr__`, which for a GPU tensor implies
  a D→H synchronisation. Adaptive `odeint` (dopri5) may call the RHS
  many thousands of times per path. Even on CPU this dominates wall
  time relative to the actual ODE evaluation. There is an equivalent
  commented-out print in `drift_numpy.py:80` that was previously
  removed.
- **Fix hint:** Remove the print or wrap in a verbose flag.

---

### BUG-23 — `drift_numpy.solve_sde` has hard-coded diagnostic indices
- **File:** `drift_numpy.py:158–160`
- **Severity:** High
- **Description:**
  ```python
  print("Velocity z-axis =", velocity[2][25, 15, 3000], ...)
  print("DL =",              dl[25, 15, 3000], ...)
  print("DT =",              dt[25, 15, 3000], ...)
  ```
  The indices `[25, 15, 3000]` are hard-coded. For a 100×100×2000 grid,
  index 3000 along the Z axis is out of bounds and will raise an
  `IndexError` at runtime. Even for larger grids, a hard-coded
  diagnostic index will silently inspect the wrong cell if the geometry
  changes.
- **Fix hint:** Remove the print or use `velocity[2][shape//4, shape//4, shape//4]`
  with shape-derived indices.

---

### BUG-24 — `drift_numpy.solve` tolerance `rtol=atol=1e-10` may be excessive
- **File:** `drift_numpy.py:107`
- **Severity:** Medium (performance)
- **Description:**
  ```python
  res = solve_ivp(func, ..., rtol=0.0000000001, atol=0.0000000001, method='Radau')
  ```
  Radau is an implicit solver designed for stiff ODEs. With tolerances
  of `1e-10` on a Python-callback RHS that calls a scipy
  `RegularGridInterpolator` on every evaluation, this will be very slow
  — each RHS call may take O(10 µs) and the solver may need O(10⁴)
  evaluations. Reasonable tolerances for drift paths in this application
  might be `1e-4` to `1e-6`.
