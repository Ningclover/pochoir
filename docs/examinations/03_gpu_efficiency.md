# GPU Running Efficiency

Primary focus: `fdm_cumba` (Numba-CUDA, the production backend).
Secondary: `fdm_cupy`, `fdm_torch` (for comparison).
Grid size reference: 100 × 100 × 2000 fp64.

---

## 1. Roofline context

The 7-point Jacobi stencil on a 3D grid is **memory-bandwidth bound**
at all realistic problem sizes.

Arithmetic intensity (AI) for one iteration:
- Reads: centre + 6 neighbours = 7 elements per voxel = 7 × 8 B = 56 B
- Writes: 1 element per voxel = 8 B
- FLOPs: 6 additions + 1 multiply = ~7 FLOP

**AI ≈ 7 FLOP / 64 B ≈ 0.11 FLOP/B**

For comparison:
- A100 SXM: memory bandwidth ~2 TB/s, FP64 peak ~10 TFLOP/s → ridge point ≈ 5 FLOP/B
- RTX 3090: memory bandwidth ~900 GB/s, FP64 peak ~560 GFLOP/s → ridge point ≈ 0.6 FLOP/B

At AI = 0.11 the computation is memory-bound on *every* consumer and
data-centre GPU. This means:
- The bottleneck is global memory bandwidth, not compute.
- Any improvement in memory access patterns (coalescing, reduced
  allocations) will directly reduce iteration time.
- Mixed-precision (fp32) would halve bandwidth, roughly doubling speed
  — but fp64 is required.

---

## 2. `fdm_cumba` (Numba-CUDA) — PRODUCTION BACKEND

### 2a. Operations per inner iteration

| Step                                   | GPU ops / kernel launches |
|----------------------------------------|--------------------------|
| `stencil(iarr_pad, tmp_pad)` → `tmp_pad[:] = 0` + kernel | 1 memset + 1 stencil kernel = **2 launches** |
| `iarr_pad[:] = bi_pad + mutable_pad*tmp_pad` (CuPy expr on cupy array) | **2 kernels** (cupy fuses `*` then `+`) |
| `edge_condition(iarr_pad, *periodic)` for 3D: 2 slice assigns per dim × 3 dims | **6 tiny kernels** |

**Total: ~10 kernel launches per iteration** (not counting implicit
CUDA stream flush).

The 6 tiny `edge_condition` kernels (`fdm_generic.py:28–32`) each
copy one face slice of `iarr_pad`. For a 102×102×2002 padded volume,
each face is either 102×102 (≈10⁴ elements) or 102×2002 (≈2×10⁵
elements) or 102×2002 — all very small. These incur significant kernel
*launch overhead* relative to their work. For 10,000 iterations, that
is 60,000 tiny kernel launches just for ghost-cell refresh.

### 2b. Host↔device synchronisation per iteration

There are **zero host-sync points in the inner loop** — all operations
are asynchronous CUDA kernel launches queued in the default stream.

Per epoch (every 100 iterations), there are **two syncs**:

1. `float(maxerr)` at `fdm_cumba.py:104` — `float()` on a 0-d cupy
   array forces a `.item()` / stream sync.
2. `{maxerr:.6e}` in the f-string at `fdm_cumba.py:105` — another
   implicit `.item()` on the same array.

One sync per epoch is fine (the convergence check is worth it).
The redundant second sync can be removed by computing `maxerr_float =
float(maxerr)` once and reusing it.

### 2c. Coalescing — the key performance problem

**Current layout:** `cuda.grid(3)` returns `(i, j, k)` with
`threadIdx.x → i`, which indexes the slowest axis (stride = n*m = 200,000).
Warp threads access addresses stride `200,000 × 8 = 1.6 MB` apart.
The GPU memory controller cannot merge these into a single transaction.

**Effect:** instead of the theoretical 1 cache line per warp (128 B),
the hardware issues up to 32 individual 128-B transactions — 32× the
memory traffic.

Estimated impact on a modern GPU:
- With correct coalescing: for 100×100×2000 fp64 (160 MB), one pass
  reads 7×160 + 1×160 = 1.28 GB; at ~500 GB/s effective bandwidth
  ≈ 2.6 ms per iteration.
- With 32× bandwidth penalty: ≈ 80 ms per iteration.
- For 10,000 iterations: 26 s vs. 800 s — roughly 30× difference.

This is the single largest performance bottleneck.

**How to fix:** Reorder the kernel index mapping:
```python
# Current (wrong coalescing):
i, j, k = cuda.grid(3)
threadsperblock = (8, 8, 16)

# Fixed (coalesced):
k, j, i = cuda.grid(3)          # k is contiguous, maps to threadIdx.x
threadsperblock = (32, 8, 4)    # or (16, 8, 8); BX*BY*BZ ≤ 1024
```
With this change, consecutive warp threads differ in `k` (stride 1),
and a single 32-thread warp covers 32 contiguous elements in the Z
direction — 256 B, one cache line — fully coalesced.

### 2d. Kernel launch configuration analysis

**3D kernel (`fdm_cumba.py:45–50`):**
- `threadsperblock = (8, 8, 16)` = 1024 threads per block (maximises
  occupancy within the 1024-thread-per-block hardware limit).
- Grid: `ceil(l/8) × ceil(n/8) × ceil(m/16)` = `13 × 13 × 125` =
  21,125 blocks for 100×100×2000 (padded 102×102×2002).
- No shared memory. Each thread fetches 7 values from global memory
  with no reuse — a missed opportunity for a tiled stencil.

**Shared-memory tiling opportunity:**
For a tile of shape `(BZ, BY, BX)` with `BX=16, BY=8, BZ=8` (1024
threads), load a `(BZ+2)×(BY+2)×(BX+2)` halo region into shared
memory: `18×10×18 × 8 B = 25,920 B` per block (well within the 48–96 KB
shared memory limit). Interior threads would then access 7 values from
shared memory (single-cycle) instead of global memory. For the 7-point
stencil with AI = 0.11 FLOP/B, tiling can reduce global traffic from
7 reads/voxel to ~1.4 reads/voxel (halo overhead ≈ 40%), a ~5× bandwidth
reduction. Combined with coalescing, this can yield 10–30× total speedup.

**2D kernel (`fdm_cumba.py:36–40`):**
- `threadsperblock = (32, 32)` = 1024 threads.
- Grid: `ceil(n/32) × ceil(m/32)`.
- Same coalescing issue: `threadIdx.x → i` (row), stride = m.
- At 2D grid sizes (100 × 2000), the 2D solve is fast regardless.

### 2e. Python loop overhead

The outer `for istep in range(epoch)` loop at `fdm_cumba.py:89` is a
Python loop. Each iteration calls:
1. `stencil(iarr_pad, tmp_pad)` — Python function call + 2 CUDA kernel launches.
2. One CuPy expression → 2 kernel launches.
3. `edge_condition(...)` → Python function call → 6 kernel launches.

Per iteration: ~6 Python function call overheads + ~10 CUDA kernel
launches. For `epoch=100` iterations (one Python epoch), that is 600
function calls + 1000 kernel launches. The kernel launches are queued
asynchronously and the GPU processes them in the background, but Python
loop overhead is ~1 µs/call so 600 calls = ~0.6 ms overhead per epoch.
For 10,000 epochs this adds ~60 s of Python overhead. Mitigatable by
fusing the loop into a device function or using `numba.cuda.stream`.

---

## 3. `fdm_cupy` — comparison

### 3a. Stencil

Uses `fdm_generic.stencil()` which performs dimension-by-dimension
slice addition on CuPy arrays. For a 3D array this is **6 slice
operations** (the `res += array[...]` accumulation in `fdm_generic.py:60, 64`)
plus one multiply (`res *= norm`, line 66). Each is a separate CuPy
kernel. Total: ~8 kernel launches per stencil call (vs. 1 for cumba's
custom kernel).

**Key difference:** cumba's custom CUDA kernel reads all 6 neighbours
in a single pass; cupy's generic path materialises 6 intermediate views.
No extra allocation occurs (slices are views), but the kernel-launch
overhead and separate cache loads for each direction are higher.

### 3b. Host↔device sync

One sync per epoch at `fdm_cupy.py:71–73`:
```python
maxerr = cupy.max(cupy.abs(err))     # async reduction, syncs at next Python step
if prec and maxerr < prec:           # forces sync by evaluating maxerr as Python bool
```
Good cadence.

### 3c. Convergence measurement coverage

As noted in `02_bugs.md` (BUG-03), cupy measures error over **1
iteration** while cumba measures over **100 iterations**. At the same
`prec`, cupy will run more iterations than cumba before stopping. This
is a cross-backend inconsistency, not a GPU efficiency issue per se.

---

## 4. `fdm_torch` — comparison

`fdm_torch` currently runs on CPU (BUG-01 in `02_bugs.md`). If fixed
to run on GPU:

### 4a. Stencil approach

Uses `fdm_generic.stencil()` — same as cupy. The stencil for a torch
tensor uses `torch` slice operations instead of cupy. PyTorch fuses
element-wise ops via its JIT, so the `res += array[...]` loop may be
partially fused. Still, 6 separate slice additions.

### 4b. Convergence gate error (BUG-02)

`maxerr < prec * check_interval` — 100× looser threshold. After fixing
BUG-01 and BUG-02, torch should converge comparably to cupy with fewer
iterations at the same effective tolerance.

---

## 5. `arrays.gradient` — hidden GPU→CPU→GPU round-trip

**File:** `arrays.py:104–111`

When `pot` is a torch tensor, computing the electric field:
```python
efield = pochoir.arrays.gradient(pot, *dom.spacing)
```
invokes:
```python
a = array.to('cpu').numpy()    # GPU→CPU (160 MB)
gvec = numpy.gradient(a, spacing)   # CPU-only, also BUG-12: missing *
g = numpy.array(gvec)          # stacks to (3,Nx,Ny,Nz) on CPU (480 MB)
return to_torch(g, device=array.device)  # CPU→GPU (480 MB)
```

Total data moved: 160 MB (D→H) + 480 MB (H→D) = 640 MB, plus the 480 MB
temporary on CPU. This is a one-time cost at the `velo` step, not inside
the FDM iteration loop, so it does not affect iteration-time benchmarks.
But it is wasteful and avoidable (`torch.gradient` exists as of
PyTorch 1.11 and handles N-D arrays with per-axis spacing).

For the normal production path (numpy `pot`), `arrays.gradient` correctly
calls `numpy.gradient(array, *spacing)` on CPU with no GPU involvement.

---

## 6. Summary comparison table

| Metric                            | `fdm_torch` (CPU) | `fdm_cupy` (GPU) | `fdm_cumba` (GPU) |
|-----------------------------------|-------------------|------------------|-------------------|
| Device                            | CPU (bug)         | GPU              | GPU               |
| Kernel launches / iter            | N/A               | ~9               | ~10               |
| Host↔device sync / epoch          | 2 (host ops)      | 1                | 2 (minor)         |
| Stencil implementation            | fdm_generic slice | fdm_generic slice| Custom CUDA kernel|
| Coalescing (3D)                   | N/A               | Depends on cupy  | **Reversed (bug)**|
| Convergence metric span           | 100 iters         | 1 iter (bug)     | 100 iters         |
| Convergence threshold             | `prec × 100` (bug)| `prec`           | `prec`            |
| Shared memory usage               | No                | No               | No                |
| Estimated iters for 100×100×2000  | Slowest           | Moderate         | Fast (if coalescing fixed) |

**Key recommendation:** Fix the coalescing in `fdm_cumba` (BUG-05).
This alone can yield a 10–30× speedup in the stencil kernel on the
100 × 100 × 2000 production grid.
