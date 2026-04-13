# pochoir Field-Response Code Examination — Index

**Reviewed code version:** commit `fe5b579` (branch `master`)  
**Package root:** `pochoir/pochoir/` (Python module)  
**Examination date:** 2026-04-13  
**Reviewer note:** This is a read-only audit. No source files were modified. Every claim cites
`file:line` so the reader can verify directly. The user should confirm physics sign conventions
independently before acting on findings related to E-field sign or Ramo orientation.

---

## Purpose

This set of four documents audits the `pochoir` codebase with four goals:

| # | Objective | Document |
|---|-----------|----------|
| 1 | Explain the general algorithm and key details | [01-algorithms.md](01-algorithms.md) |
| 2 | Identify potential bugs | [02-potential-bugs.md](02-potential-bugs.md) |
| 3 | Examine GPU (and CPU) running efficiency | [03-gpu-efficiency.md](03-gpu-efficiency.md) |
| 4 | Inventory memory usage and identify savings | [04-memory-usage.md](04-memory-usage.md) |

---

## Scope

### In scope
- The five FDM back-ends: `fdm_numpy.py`, `fdm_numba.py`, `fdm_torch.py`, `fdm_cupy.py`, `fdm_cumba.py`
- The FDM stencil and edge condition: `fdm_generic.py`
- Array utilities: `arrays.py`
- Drift back-ends: `drift_numpy.py`, `drift_torch.py`
- Ramo calculations: `srdot.py`
- CLI plumbing for: `fdm`, `velo`, `grad`, `drift`, `induce`, `srdot`, `bc-interp` commands in `__main__.py`
- Supporting: `bc_interp.py`, `domain.py`, `lar.py`, `units.py`
- Storage layer (bug-only): `persist.py`, `npz.py`, `hdf.py`, `main.py`

### Out of scope (mentioned only where they affect dtypes or memory)
- Plotting: `plots.py`, `vtkexport.py`
- Config/Jsonnet: `jsonnet.py`, `gencfg.py`
- PCB / shape generators: `gen_pcb_*.py`, `gen_sandh*.py`, `gen.py`, `examples.py`
- Test harness: `test/`
- HTML documentation: `*.org`, `*.html`

---

## Canonical pipeline

Each `pochoir <subcommand>` is a fresh Python process. Data is exchanged via an on-disk store
(NPZ directory or HDF5 file). No GPU state survives between commands.

```
domain
  │
  ├─ init / gen  ─────────────────────────────── paints IVA + BVA on the grid
  │
  ├─ fdm  ──[numpy|numba|torch|cupy|cumba]────── solves Laplace, writes potential
  │
  ├─ velo ──────────────────────────────────────  gradient → E-field → µ(E) → velocity
  │
  ├─ starts  ────────────────────────────────────  stores seed points
  │
  ├─ drift ──[numpy|torch]──────────────────────  integrates paths through velocity field
  │
  ├─ induce ─────────────────────────────────────  dQ/dT from weighting potential on path
  │
  └─ srdot ──────────────────────────────────────  Ramo dot product  -q·E_w·v
```

A 2D→3D lifting sub-flow also exists:
```
fdm (2D) → bc-interp → fdm (3D) → extendwf
```

---

## Top-level findings summary

| Category | Count | Highest severity |
|----------|-------|-----------------|
| Import / crash bugs (Category A) | 7 | Will crash on modern numpy/torch |
| Numerical / algorithm correctness (Category B) | 8 | Stencil in wrong dtype; gradient unpacked wrong |
| Engine-specific logic (Category C) | 5 | 3D CUDA kernel broken; drift_torch never on GPU |
| Hard-coded assumptions / fragile code (Category D) | 9 | Domain hard-coded in extendwf |
| GPU efficiency issues | 6 major | Only FDM runs on GPU; per-step Python loops |
| Memory waste opportunities | 8 | Dead tensors; float64 everywhere |

See each document for details with file:line citations.

---

## Key files for quick navigation

| File | Role | Key lines |
|------|------|-----------|
| `fdm_generic.py` | Stencil kernel + edge condition | `:35-67` stencil, `:3-32` edge_condition |
| `fdm_torch.py` | GPU FDM (PyTorch) | `:44-75` |
| `fdm_cupy.py` | GPU FDM (CuPy) | `:38-79` |
| `fdm_cumba.py` | GPU FDM (numba-CUDA) | `:13-95` |
| `fdm_numpy.py` | Reference CPU FDM | `:17-74` |
| `fdm_numba.py` | JIT-compiled CPU FDM | `:7-41` |
| `drift_torch.py` | "Torch" drift (actually CPU) | `:63-75` |
| `drift_numpy.py` | scipy-based drift | `:81-97` |
| `arrays.py` | Array utilities + gradient | `:96-111` gradient, `:33-44` module dispatch |
| `srdot.py` | Ramo dot product | `:6-42` |
| `bc_interp.py` | 2D→3D BC painting | `:8-44` |
| `__main__.py` | All CLI commands | `:296-333` fdm, `:345-360` velo, `:403-447` drift, `:573-645` induce, `:720-749` srdot |
| `lar.py` | LAr mobility function | `:10-51` |
