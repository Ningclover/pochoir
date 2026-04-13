# Memory Inventory and Reduction Opportunities

Grid reference: 100 × 100 × 2000, fp64 (8 bytes/element).

```
Elements per scalar volume:   100 × 100 × 2000 = 20,000,000
Bytes per fp64 scalar volume: 20,000,000 × 8 B = 160 MB
Bytes per bool mask:          20,000,000 × 1 B = 20 MB
Padded volume (102×102×2002): 20,824,824 × 8 B ≈ 167 MB (padded fp64)
Padded bool mask:             20,824,824 × 1 B ≈ 21 MB
2D slice (100×2000) fp64:     2,000,000 × 8 B = 16 MB
```

At the current grid size (~160 MB / volume), peak GPU memory during the
FDM solve is approximately 1.0–1.1 GB — well within the capacity of any
modern GPU (≥ 8 GB VRAM). **Memory is not a crisis at this grid size.**
The focus of this section is therefore on eliminating waste and
documenting future scaling paths.

---

## 1. `fdm_cumba.solve` — GPU memory at peak

Arrays allocated in `fdm_cumba.solve` (`fdm_cumba.py:61–93`):

| Array        | Shape                    | dtype | On device? | Bytes    | Notes |
|--------------|--------------------------|-------|------------|----------|-------|
| `iarr_pad`   | (102, 102, 2002)         | fp64  | GPU        | 167 MB   | Working potential; the main array |
| `barr_pad`   | (102, 102, 2002)         | bool  | GPU        | 21 MB    | BC mask (padded) |
| `bi_pad`     | (102, 102, 2002)         | fp64  | GPU        | 167 MB   | Fixed values (= iarr*barr, padded) |
| `mutable_pad`| (102, 102, 2002)         | bool  | GPU        | 21 MB    | Free-cell mask (padded) |
| `tmp_pad`    | (102, 102, 2002)         | fp64  | GPU        | 167 MB   | Stencil output buffer |
| `err`        | (100, 100, 2000)         | fp64  | GPU        | 160 MB   | **Dead allocation** (overwritten) |
| `prev`       | (100, 100, 2000)         | fp64  | GPU        | 160 MB   | Snapshot for convergence check |

**Peak GPU usage during solve: ~863 MB** (5 fp64 + 2 bool volumes).

With `prev` and `err` counted (both alive simultaneously at epoch end):
~863 + 160 (prev, already in the table) = **~863 MB peak**.

### Waste

- **`err = cupy.zeros_like(iarr)` at `fdm_cumba.py:66`** allocates a
  160 MB fp64 array that is immediately overwritten at `fdm_cumba.py:101`
  without any use of the initial zeros. This is 160 MB of wasted
  allocation + one zero-init kernel launch per solve call. **Delete line 66.**

- **`barr_pad` is never read after line 62.** It is only used to compute
  `bi_pad` and `mutable_pad` at lines 63–64, then never referenced again.
  It could be freed (or computed inline) after those two lines.
  Saving: **21 MB GPU** (minor, but keeps the memory accounting clean).

---

## 2. `fdm_cupy.solve` — GPU memory at peak

| Array          | Shape              | dtype | Bytes    | Notes |
|----------------|--------------------|-------|----------|-------|
| `iarr`         | (100, 100, 2000)   | fp64  | 160 MB   | Input copy on GPU |
| `barr`         | (100, 100, 2000)   | bool  | 20 MB    | Input copy |
| `bi_core`      | (100, 100, 2000)   | fp64  | 160 MB   | Fixed values (unpadded) |
| `mutable_core` | (100, 100, 2000)   | bool  | 20 MB    | Free-cell mask (unpadded) |
| `tmp_core`     | (100, 100, 2000)   | fp64  | 160 MB   | Stencil output |
| `err`          | (100, 100, 2000)   | fp64  | 160 MB   | **Dead** (`cupy.zeros_like(iarr)` at line 45) |
| `ifixed`       | (100,100,2000)     | bool  | 20 MB    | **Dead** (line 51, never used) |
| `fixed`        | variable           | fp64  | small    | **Dead** (line 52, never used) |
| `barr_pad`     | (102, 102, 2002)   | bool  | 21 MB    | Ghost-padded mask |
| `iarr_pad`     | (102, 102, 2002)   | fp64  | 167 MB   | Working array |
| `prev`         | (100, 100, 2000)   | fp64  | 160 MB   | Convergence snapshot |

**Peak GPU usage: ~1,048 MB** (with dead arrays included).

**After removing dead allocations (lines 45, 51–52): ~868 MB peak.**

Compared to cumba: cupy keeps `bi_core`, `mutable_core`, `tmp_core` at
*unpadded* shape (100×100×2000 vs. 102×102×2002), saving ~21 MB each
— a slight win vs. cumba's padded auxiliaries.

### Dead allocations to remove

| Line          | Array      | Size | Action |
|---------------|-----------|------|--------|
| `fdm_cupy.py:45` | `err = cupy.zeros_like(iarr)` | 160 MB | Delete — overwritten at line 70 |
| `fdm_cupy.py:51` | `ifixed`   | 20 MB | Delete |
| `fdm_cupy.py:52` | `fixed`    | small | Delete |

---

## 3. `fdm_torch.solve` — CPU memory at peak (currently CPU-only)

Since `fdm_torch` runs on CPU (BUG-01), its memory sits in RAM, not GPU VRAM.
The array inventory is structurally identical to cupy (unpadded auxiliaries):

| Array          | Shape            | dtype | Bytes  |
|----------------|------------------|-------|--------|
| `bi_core`      | (100,100,2000)   | fp64  | 160 MB |
| `mutable_core` | (100,100,2000)   | bool  | 20 MB  |
| `tmp_core`     | (100,100,2000)   | fp64  | 160 MB |
| `barr_pad`     | (102,102,2002)   | bool  | 21 MB  |
| `iarr_pad`     | (102,102,2002)   | fp64  | 167 MB |
| `prev`         | (100,100,2000)   | fp64  | 160 MB |

Peak CPU RAM during torch solve: **~688 MB**.

---

## 4. Pipeline-level memory (`velo` command)

`__main__.velo` at `__main__.py:350–444` computes the E-field and
velocity field. All computation is on CPU (numpy) in the normal path.

### Sequence of allocations

| Step | Code (approx)              | New arrays created       | Size         |
|------|----------------------------|--------------------------|--------------|
| Load | `pot = ctx.obj.get(...)` (line 355) | `pot` (fp64) | 160 MB |
| Load | `barr = ctx.obj.get(...)` (line 359)| `barr` (bool)| 20 MB |
| Gradient | `efield = arrays.gradient(pot, ...)` (line 362) | `numpy.gradient` returns list of 3 × 160 MB; `numpy.array(...)` stacks to (3,Nx,Ny,Nz) | 480 MB + 480 MB simultaneous = **960 MB transient** |
| After gradient | efield list freed | efield = 480 MB; list freed | |
| BC mask | `flag = barr==1` (line 363) | bool array | 20 MB |
| Scale | `efield *= units.V` (line 395) | in-place, no new alloc | |
| vmag | `emag = vmag(efield)` (line 402) | internally: [c*c for c in efield] = 3×160 MB + zeros_like = 160 MB → freed after return | 160 MB net |
| mobility | `mu = lar.mobility(emag,temp)` (line 403) | `mu` fp64 | 160 MB |
| diff | `dl = lar.diff_longit(...)` (line 405) | `dl` fp64 | 160 MB |
| diff | `dt = lar.diff_tran(...)` (line 407)  | `dt` fp64 | 160 MB |
| varr list | `[e*mu/mm**2 for e in efield]` (line 408) | list of 3×160 MB | 480 MB |
| varr stack | `varr = numpy.array(varr)` (line 409) | (3,Nx,Ny,Nz) stacked | 480 MB |

**Peak memory during `velo`** (at the moment `numpy.array(varr)` is
formed, with `varr` list + stacked `varr` both alive):

```
pot      160 MB
barr      20 MB
efield   480 MB (stacked gradient)
flag      20 MB
emag     160 MB
mu       160 MB
dl       160 MB  (if used)
dt       160 MB  (if used)
varr_list 480 MB  (list of 3 arrays before stacking)
varr_stack 480 MB (stacked output, momentarily coexistent)
─────────────────
Peak:   ~2,280 MB (without dl/dt)   ~2,600 MB (with dl+dt)
```

After `varr = numpy.array(varr)` the list is freed:
```
Steady state: pot + barr + efield + flag + emag + mu + varr ≈ 1,500 MB
```

This is a significant RAM footprint for the `velo` step. None of the
large arrays are explicitly freed (`del`) before saving.

### Memory reduction opportunities (velo)

1. **`del pot` after line 362 (after efield is computed)**
   Saves 160 MB once efield is formed and pot is no longer needed.

2. **`del efield` after line 408 (after varr is computed)**
   Saves 480 MB once the velocity field is formed.

3. **Avoid the double-copy in `numpy.array(numpy.gradient(...))`**
   (`arrays.py:102`): `numpy.gradient` returns a Python list of 3 arrays
   (total 480 MB). Wrapping with `numpy.array()` creates a new stacked
   (3,N,N,N) array (another 480 MB) while the list is still alive.
   Use `numpy.stack([...])` or pre-allocate and compute in-place to
   halve the transient.

4. **`del emag` after mu and diffusion coefficients are computed**
   `emag` is only needed for `mu`, `dl`, `dt`. After line 407 it can
   be freed, saving 160 MB.

With all four changes, peak during `velo` drops from ~2,280 MB to
approximately **~1,200 MB** (efield + mu + varr stack + dl + dt).

---

## 5. `extendwf` — CPU memory for the splice

`extendwf` at `__main__.py:627–682` creates the spliced volume:

```python
arr = numpy.zeros((newXdim, dom3D.shape[1], dom2D.shape[1]))
```

With `newXdim = sol2D.shape[0]` and the geometry above:
- If `sol2D` represents the full X extent for 7+ strips,
  `sol2D.shape[0]` could be ~700 (7 strips × 100 voxels each).
- Output shape: `(700, 100, 2000)` fp64 = **1,120 MB** (~1.1 GB).

This is created while `sol2D` (2D, ~100×2000 = 16 MB) and `sol3D`
(3D at 100×100×2000 = 160 MB) are also live:

**Peak for extendwf: ~1,296 MB** (sol2D + sol3D + arr).

This is manageable (CPU RAM) but could be reduced by processing the
output array in X-strips rather than allocating the full volume at once.

---

## 6. Summary — most impactful memory improvements (no code changes made)

| Change | File:line | Savings | Effort |
|--------|-----------|---------|--------|
| Remove dead `err` allocation | `fdm_cumba.py:66`, `fdm_cupy.py:45` | 160 MB GPU each | 1 line each |
| Remove dead `ifixed`, `fixed` | `fdm_cupy.py:51–52` | 20 MB GPU | 2 lines |
| `del pot` after gradient | `__main__.py` after line 362 | 160 MB CPU | 1 line |
| `del efield` after varr | `__main__.py` after line 408 | 480 MB CPU | 1 line |
| `del emag` after diffusion | `__main__.py` after line 407 | 160 MB CPU | 1 line |
| Fix `numpy.array(gradient(...))` transient | `arrays.py:102` | 480 MB CPU (transient) | 1 line |
| Avoid `barr_pad` persistence in cumba | `fdm_cumba.py:62` | 21 MB GPU | 1 line |

**Total potential savings: ~1.5 GB CPU peak, ~0.3 GB GPU peak.**

At the current grid size these are quality-of-life improvements. As the
grid size scales (e.g. doubling Z to 4000 or adding more strips), the
pipeline-level coexistence in `velo` and the `extendwf` full allocation
will become the binding constraints.
