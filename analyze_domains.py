#!/usr/bin/env python3
import numpy as np

# Domain definitions from test-full-3d.sh
domains = {
    'drift3d': {
        'shape': (25, 17, 2000),
        'spacing': 0.1,  # mm
        'purpose': 'drift field'
    },
    'weight2d': {
        'shape': (1092, 2000),  # 2D only
        'spacing': 0.1,  # mm
        'purpose': 'weighting field 2D'
    },
    'weight3d': {
        'shape': (350, 32, 2000),
        'spacing': 0.1,  # mm
        'purpose': 'weighting field 3D'
    }
}

print("=" * 70)
print("DOMAIN ANALYSIS")
print("=" * 70)

for name, dom in domains.items():
    print(f"\n{name.upper()}:")
    print(f"  Shape: {dom['shape']}")
    print(f"  Spacing: {dom['spacing']} mm")
    
    if len(dom['shape']) == 3:
        size = tuple(s * dom['spacing'] for s in dom['shape'])
        print(f"  Physical size (mm): {size[0]:.1f} × {size[1]:.1f} × {size[2]:.1f}")
        print(f"  Purpose: {dom['purpose']}")
    else:  # 2D
        size = tuple(s * dom['spacing'] for s in dom['shape'])
        print(f"  Physical size (mm): {size[0]:.1f} × {size[1]:.1f} (2D)")
        print(f"  Purpose: {dom['purpose']}")

print("\n" + "=" * 70)
print("OVERLAP ANALYSIS")
print("=" * 70)

print("\n1. drift3d vs weight3d:")
drift_size = (25 * 0.1, 17 * 0.1, 2000 * 0.1)
weight3d_size = (350 * 0.1, 32 * 0.1, 2000 * 0.1)
print(f"   drift3d:  {drift_size[0]:.1f} × {drift_size[1]:.1f} × {drift_size[2]:.1f} mm")
print(f"   weight3d: {weight3d_size[0]:.1f} × {weight3d_size[1]:.1f} × {weight3d_size[2]:.1f} mm")
print(f"   Z-dimension: Same length ({drift_size[2]:.1f} mm)")
print(f"   X-dimension: drift3d ({drift_size[0]:.1f} mm) < weight3d ({weight3d_size[0]:.1f} mm)")
print(f"   Y-dimension: drift3d ({drift_size[1]:.1f} mm) < weight3d ({weight3d_size[1]:.1f} mm)")
print(f"   → drift3d is SMALLER and likely CONTAINED within weight3d region")

print("\n2. weight2d vs weight3d:")
weight2d_size = (1092 * 0.1, 2000 * 0.1)
print(f"   weight2d: {weight2d_size[0]:.1f} × {weight2d_size[1]:.1f} mm (2D cross-section)")
print(f"   weight3d: {weight3d_size[0]:.1f} × {weight3d_size[1]:.1f} × {weight3d_size[2]:.1f} mm")
print(f"   X-dimension: weight2d ({weight2d_size[0]:.1f} mm) > weight3d ({weight3d_size[0]:.1f} mm)")
print(f"   Z-dimension: Same length ({weight2d_size[1]:.1f} mm = {weight3d_size[2]:.1f} mm)")
print(f"   → weight3d is CONTAINED within the X-Z plane of weight2d")

print("\n3. Summary:")
print("   - These are NOT overlapping regions in physical space")
print("   - They represent DIFFERENT FIELDS in the SAME or related geometry:")
print("     * drift3d: Small unit cell for DRIFT FIELD")
print("     * weight2d: Large 2D slice for WEIGHTING FIELD") 
print("     * weight3d: Medium 3D volume for WEIGHTING FIELD")
print("   - The domains define computational grids, not physical boundaries")

