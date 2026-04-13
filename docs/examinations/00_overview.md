# Overview: pochoir Field-Response Solver

*Examination of code at `pochoir/` — read-only analysis, no code
changes. All file:line citations refer to the repository root.*

---

## 1. What the code does

`pochoir` computes **field responses** (and weighting fields) for
liquid-argon detector readout electrodes (pixels, strips, PCBs).
The core computation is:

1. **FDM solve** — Solve Laplace's equation ∇²V = 0 on a regular grid
   under Dirichlet boundary conditions (electrodes at fixed potentials).
2. **Gradient** — Derive the electric field E = −∇V from the potential V.
3. **Drift** — Trace ionisation-electron drift paths through E, including
   optional longitudinal/transverse diffusion.
4. **Response** (out of scope for this examination) — Fold the drift
   paths into Ramo-theorem induced-current waveforms.

---

## 2. Module map — FDM backends

```
pochoir/fdm.py               ← dispatch: imports solve_numpy, solve_torch,
│                              solve_numba, solve_cupy, solve_cumba
│                              (each protected by try/except ImportError)
├── fdm_generic.py           ← shared helpers
│   ├── stencil()            ← N-D uniform-average stencil (5-pt 2D, 7-pt 3D)
│   └── edge_condition()     ← ghost-layer refresh: periodic wrap or Neumann reflect
│
├── fdm_numpy.py             ← reference CPU backend (uses fdm_generic.stencil)
├── fdm_numba.py             ← Numba JIT CPU backend (hard-coded 2D/3D kernels)
├── fdm_torch.py             ← "torch GPU" backend — NOTE: currently CPU-only (bug)
├── fdm_cupy.py              ← CuPy GPU backend (uses fdm_generic.stencil via CuPy)
└── fdm_cumba.py             ← Numba-CUDA GPU backend (PRIMARY, custom kernels)
                               stencil_numba2d_jit, stencil_numba3d_jit
```

Callers select a backend by importing the desired `solve_*` symbol
directly; there is no runtime dispatch table in `fdm.py`.

---

## 3. Module map — drift backends

```
pochoir/drift.py             ← dispatch: imports solve_numpy, solve_torch,
│                              solve_scipy, solve_numpyold
│
├── drift_numpy.py           ← CPU backends
│   ├── Simple               ← velocity interpolator (scipy RGI)
│   ├── solve()              ← scipy Radau IVP solver
│   └── solve_sde()          ← explicit Euler-Maruyama SDE integrator
│
└── drift_torch.py           ← "torch" backend (NOTE: currently CPU-only, bug)
    ├── Simple               ← velocity interpolator (torch_interpolations RGI)
    └── solve()              ← torchdiffeq.odeint (dopri5 adaptive RK)
```

---

## 4. CLI pipeline — end-to-end data flow

The CLI (`__main__.py`) exposes sub-commands that can be chained.
Each sub-command is normally a **separate process invocation** — memory
is not shared between them unless a single-process scripted chain is used.

```
fdm  ──►  potential (V)         ─┐
          boundary mask (barr)   │   velo  ──►  velocity field (varr)  ──►  drift  ──►  paths
                                  └►              │
                                                  ▼
                                             arrays.gradient
                                             (GPU→CPU→GPU round-trip if torch)
```

For the 2D + 3D workflow used in production:

```
fdm (2D)  ──►  sol2D  ─┐
                        ├─► bc-interp  ──►  initial3D + boundary3D
fdm (3D)  ──►  sol3D  ─┘

fdm (3D with 2D BCs)  ──►  sol3D_full

sol2D + sol3D_full  ──►  extendwf  ──►  full-volume weighting potential
                                         (spliced at cut_z=1100, hard-coded)
```

Relevant sub-command entry points in `pochoir/__main__.py`:

| Sub-command | Entry point      | Lines         |
|-------------|------------------|---------------|
| `fdm`       | `fdm()`          | 297–334       |
| `velo`      | `velo()`         | 350–444       |
| `drift`     | `drift()`        | 530–572       |
| `bc-interp` | `bc_interp()`    | 591–615       |
| `extendwf`  | `extendwf()`     | 617–682       |

The 2D→3D lift logic is in `pochoir/bc_interp.py:interp()`.

---

## 5. Array backend abstraction — `arrays.py`

`pochoir/arrays.py` provides a flat collection of free functions that
dispatch based on the runtime type of the input array:

| Function        | Purpose                                     |
|-----------------|---------------------------------------------|
| `module(array)` | Returns `numpy`, `torch`, or `cupy`         |
| `to_numpy(arr)` | D→H copy for torch/cupy; identity for numpy |
| `to_torch(arr)` | Always creates a new CPU tensor             |
| `to_device(arr)`| Calls `to_torch` or `to_numpy`             |
| `gradient(arr)` | ∇V via `numpy.gradient`; GPU path: D→H→D   |
| `vmag(vfield)`  | L2 norm of a vector field                  |
| `dup(arr)`      | Copy of an array                           |

There is **no persistent GPU Array class** — every `to_numpy` /
`to_torch` call allocates a fresh object.

---

## 6. Representative grid size

| Dimension | Size |
|-----------|------|
| X (strip/pixel direction) | ~100 voxels |
| Y (strip depth)           | ~100 voxels |
| Z (drift direction)       | ~2000 voxels |
| Total elements (3D)       | 20 × 10⁶    |
| Per fp64 scalar volume    | 160 MB       |
| Per bool mask             | 20 MB        |

The 2D solve runs on a 100 × 2000 slice (1.6 MB) — negligible.
The full 3D volume fits comfortably on any modern GPU.
