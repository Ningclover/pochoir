# Summary: Prioritised Findings

Grid: 100 × 100 × 2000, fp64. Primary backend: `fdm_cumba`.

Severity: **B** = Blocker (wrong results silently),
**H** = High (crash or gross error), **M** = Medium, **L** = Low.

---

## Priority table

| ID     | Finding | Sev. | File:line | Effort to fix | Expected benefit |
|--------|---------|------|-----------|---------------|-----------------|
| BUG-05 | `fdm_cumba` CUDA kernel: coalescing reversed — `threadIdx.x` drives slowest axis (stride 200k) | M | `fdm_cumba.py:14–29, 45` | 1–2 lines: swap `k,j,i = cuda.grid(3)` + reorder block dims | **10–30× iteration speedup** |
| BUG-01 | `fdm_torch` tensors never moved to GPU — no device= arg on any torch.tensor() | B | `fdm_torch.py:44–49` | Add `device=` kwarg to 5 calls | Enables torch GPU path |
| BUG-02 | `fdm_torch` precision gate is 100× looser than cupy/cumba (`prec * check_interval`) | B | `fdm_torch.py:78` | Remove `* check_interval` | Corrects cross-backend convergence parity |
| BUG-03 | `fdm_cupy` measures error over 1 iteration; torch/cumba measure over 100 | B | `fdm_cupy.py:60–70` | Adopt cumba-style `check_interval=100` look-back | Corrects cross-backend convergence parity |
| BUG-12 | `arrays.gradient` missing `*` unpack for spacing in torch path: `numpy.gradient(a, spacing)` should be `...*spacing` | B | `arrays.py:109` | Add `*`: one character | Fixes wrong gradient values for torch path |
| BUG-16 | `extendwf`: `cut_z = 1100` hard-coded (splice Z-plane) | B* | `__main__.py:643` | Compute from domain | Correctness for non-standard geometry |
| BUG-18 | `extendwf`: new domain spacing hard-coded to 0.1, origin to (0,0,0) | B* | `__main__.py:676` | Inherit from input domains | Correct E-field scaling in velo/drift |
| BUG-21 | `drift_torch.solve` hardcodes `device='cpu'` — torch drift path never uses GPU | B | `drift_torch.py:67` | Change to configurable device | Enables GPU drift |
| BUG-22 | `drift_torch.Simple.__call__` prints tensor repr on every RHS call (sync + slow) | H | `drift_torch.py:50` | Delete or guard the print | Large performance gain in drift tracing |
| BUG-23 | `drift_numpy.solve_sde` hard-coded diagnostic index `[25,15,3000]` out of bounds for 100×100×2000 | H | `drift_numpy.py:158–160` | Remove or use shape-relative indices | Prevents IndexError at runtime |
| BUG-13 | `arrays.dup` passes `requires_grad=False` to `torch.clone` — invalid kwarg, will raise | H | `arrays.py:131` | Use `.clone().detach()` | Prevents crash |
| BUG-17 | `extendwf`: `onestrip = dom3D.shape[0]/7.0` hard-coded 7-strip assumption | M | `__main__.py:646` | Parameter or compute from geometry | Correctness for other geometries |
| BUG-19 | `bc_interp`: far-Z face set to `sol2D[..., 1100]` — same hard-coded Z-index | M | `bc_interp.py:48` | Link to `cut_z` parameter | Consistency |
| BUG-20 | `bc_interp.interp` mutates `barr3D` in-place without documentation | M | `bc_interp.py:29–30, 49` | Document or copy first | Avoids silent caller-side corruption |
| BUG-04 | `fdm_cumba`: BC update writes full padded volume then `edge_condition` clobbers halo | M | `fdm_cumba.py:96` | Update only `[core]` | Saves ~1 padded-volume write/iter |
| BUG-07 | `fdm_cupy`: `maxerr` may be unbound in final print if loop never set it | M | `fdm_cupy.py:77` | Guard with `if prev is not None` | Prevents NameError |
| BUG-08 | `fdm_cupy`: `cupy.zeros(iarr.shape)` defaults to fp64 regardless of iarr dtype | M | `fdm_cupy.py:43` | Add `dtype=iarr.dtype` | Correct type propagation |
| BUG-14 | `arrays.vmag` uses `numpy.zeros_like` on a possibly-torch input | M | `arrays.py:120` | Use `arrays.module(...)` | Prevents silent type corruption |
| BUG-15 | `arrays.to_torch` always goes through CPU even for GPU inputs | M | `arrays.py:83–84` | Use `torch.as_tensor` for numpy, DLPack for cupy | Avoids D→H→D round-trip |
| BUG-09 | `edge_condition` non-periodic branch is Neumann, not Dirichlet ("fixed" comment misleading) | M | `fdm_generic.py:30–32` | Rename comment to `# Neumann: zero gradient` | Prevents misunderstanding in future edits |
| BUG-24 | `drift_numpy.solve`: Radau with `rtol=atol=1e-10` on Python RHS may be very slow | M | `drift_numpy.py:107` | Loosen to 1e-6, benchmark | Large speedup in drift tracing |
| BUG-10 | `fdm_numpy`: `maxerr` unbound if `nepochs=0` | L | `fdm_numpy.py:73` | Initialise to `float('inf')` | Prevents edge-case crash |
| BUG-06 | `fdm_cupy`: dead `ifixed`/`fixed` never read | L | `fdm_cupy.py:51–52` | Delete | 20 MB GPU + cleaner code |
| BUG-11 | `set_core1`/`set_core2` identical bodies, misleading names | L | `fdm_numpy.py:11–15` | Merge into one function | Code clarity |

*B* = Blocker for geometries other than the current hard-coded one;
effectively Medium for the current geometry.

---

## Grouped priority list

### Fix first (blockers affecting results today)

1. **BUG-05** — Coalescing reversed in `fdm_cumba` 3D kernel. This is
   the largest single performance win: 10–30× iteration speedup with a
   one-line axis-order swap. No numerical change, pure performance.

2. **BUG-02 + BUG-03** — Convergence thresholds are inconsistent across
   backends. Fix before doing any cross-backend comparison. BUG-03 is
   also present in the numpy reference backend and should be corrected
   first since numpy is the "truth".

3. **BUG-12** — Wrong gradient values for the torch path due to missing
   `*` unpack. One character fix, but produces silently wrong electric
   fields if the torch backend is ever used.

4. **BUG-21 + BUG-22** — `drift_torch` is CPU-only and the per-step
   print kills performance. Fix together.

5. **BUG-23** — Out-of-bounds index in `solve_sde` will crash on the
   current 100×100×2000 grid. Fix immediately.

### Fix second (latent, triggered by geometry changes)

6. **BUG-16 + BUG-17 + BUG-18 + BUG-19** — All the hard-coded constants
   in `extendwf` and `bc_interp`. Currently work for the current geometry
   but will fail silently or crash for any geometry change.

### Fix when convenient (quality and robustness)

7. **BUG-01** — Torch FDM backend on GPU.
8. **BUG-13** — `dup` will crash if ever called on a torch tensor.
9. **BUG-04** — Wasted halo writes in cumba (minor bandwidth).
10. **Dead-code cleanup**: BUG-06, BUG-11, memory dead allocations.

---

## Memory savings available (no code changes yet)

| Location | Action | CPU savings | GPU savings |
|----------|--------|-------------|-------------|
| `fdm_cumba.py:66` | Remove dead `err` alloc | — | 160 MB |
| `fdm_cupy.py:45,51–52` | Remove dead `err`, `ifixed`, `fixed` | — | 180 MB |
| `__main__.py` after line 362 | `del pot` | 160 MB | — |
| `__main__.py` after line 407 | `del emag` | 160 MB | — |
| `__main__.py` after line 408 | `del efield` | 480 MB | — |
| `arrays.py:102` | Avoid list+stack double-copy in gradient | 480 MB (transient) | — |

At the current grid, total: ~1,280 MB CPU + ~340 MB GPU recoverable
by simple `del` calls and one one-liner change in `arrays.gradient`.

---

## What to watch if you scale the grid

- **Doubling Z to 4000:** all volumes double (160 → 320 MB). Still fits
  in GPU VRAM, but `velo` peak on CPU exceeds ~5 GB. Add `del pot` and
  `del efield` before scaling.
- **`extendwf` output:** for 7+ strips with 100-voxel X extent and Z=2000,
  output is already ~1.1 GB on CPU. For Z=4000 this doubles to ~2.2 GB.
- **FDM convergence:** Jacobi on an N₁×N₂×N₃ grid converges in
  O((max(Nᵢ))²) iterations. For Z=2000, that is O(4×10⁶) iterations
  at worst. The coalescing fix (BUG-05) is critical before scaling.
