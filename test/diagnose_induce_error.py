#!/usr/bin/env python3
"""
Diagnostic script to investigate the 'induce' command out-of-bounds error.
Run from pochoir/test directory.
"""

import numpy as np
import json
import sys

print("="*70)
print("DIAGNOSTIC: pochoir induce out-of-bounds error")
print("="*70)

# Load drift paths
print("\n1. Loading drift paths...")
paths_data = np.load('store/paths/drift3d.npz')
paths = paths_data['drift3d']
print(f"   Paths shape: {paths.shape} (particles, timesteps, dims)")

# Load extended weighting domain info
print("\n2. Loading extended weighting potential domain...")
with open('store/domain/weight3dextend.json', 'r') as f:
    weight_domain = json.load(f)

weight_shape = np.array(weight_domain['shape'])
weight_spacing = np.array(weight_domain['spacing'])
weight_origin = np.array(weight_domain.get('origin', [0, 0, 0]))

print(f"   Shape: {weight_shape}")
print(f"   Spacing: {weight_spacing} mm")
print(f"   Origin: {weight_origin} mm")

weight_bounds_max = weight_origin + weight_shape * weight_spacing
print(f"   Physical bounds:")
print(f"     X: [{weight_origin[0]:.3f}, {weight_bounds_max[0]:.3f}] mm")
print(f"     Y: [{weight_origin[1]:.3f}, {weight_bounds_max[1]:.3f}] mm")
print(f"     Z: [{weight_origin[2]:.3f}, {weight_bounds_max[2]:.3f}] mm")

# Check original paths bounds
print("\n3. Original drift paths bounds:")
for dim, name in enumerate(['X', 'Y', 'Z']):
    path_min = paths[:,:,dim].min()
    path_max = paths[:,:,dim].max()
    print(f"   {name}: [{path_min:7.3f}, {path_max:7.3f}] mm")

# Simulate the shift that induce command applies
print("\n4. Simulating induce command path transformations...")

# Based on __main__.py lines 752-771, the induce command shifts paths
# For the 3-view configuration, it appears to use line 761:
# newpath = [[x[0]+i*1.0*dx, x[1]+1.45, x[2]] for x in the_paths[j]]

# Estimate nstrips (this should come from command line or config)
# Looking at the extendwf metadata, nstrips = 10
nstrips = 10
dx = weight_shape[0] * weight_spacing[0] / nstrips
shift_y = 1.45  # Hardcoded in line 761

print(f"   Number of strips: {nstrips}")
print(f"   X spacing between strips (dx): {dx:.3f} mm")
print(f"   Y shift applied: {shift_y:.3f} mm")

print("\n5. Checking shifted paths bounds:")
all_within_bounds = True

for strip_idx in range(int(nstrips)):
    # Simulate shift for this strip
    shifted_paths_x_min = paths[:,:,0].min() + strip_idx * dx
    shifted_paths_x_max = paths[:,:,0].max() + strip_idx * dx
    shifted_paths_y_min = paths[:,:,1].min() + shift_y
    shifted_paths_y_max = paths[:,:,1].max() + shift_y
    shifted_paths_z_min = paths[:,:,2].min()
    shifted_paths_z_max = paths[:,:,2].max()

    # Check bounds
    x_ok = (shifted_paths_x_min >= weight_origin[0] and
            shifted_paths_x_max <= weight_bounds_max[0])
    y_ok = (shifted_paths_y_min >= weight_origin[1] and
            shifted_paths_y_max <= weight_bounds_max[1])
    z_ok = (shifted_paths_z_min >= weight_origin[2] and
            shifted_paths_z_max <= weight_bounds_max[2])

    status = "✓ OK" if (x_ok and y_ok and z_ok) else "✗ OUT OF BOUNDS"

    print(f"\n   Strip {strip_idx}:")
    print(f"     X: [{shifted_paths_x_min:7.3f}, {shifted_paths_x_max:7.3f}] mm - {'✓' if x_ok else '✗ OOB'}")
    print(f"     Y: [{shifted_paths_y_min:7.3f}, {shifted_paths_y_max:7.3f}] mm - {'✓' if y_ok else '✗ OOB'}")
    print(f"     Z: [{shifted_paths_z_min:7.3f}, {shifted_paths_z_max:7.3f}] mm - {'✓' if z_ok else '✗ OOB'}")

    if not (x_ok and y_ok and z_ok):
        all_within_bounds = False
        print(f"     {status}")

        if not x_ok:
            if shifted_paths_x_max > weight_bounds_max[0]:
                print(f"       X exceeds upper bound by {shifted_paths_x_max - weight_bounds_max[0]:.3f} mm")
            if shifted_paths_x_min < weight_origin[0]:
                print(f"       X below lower bound by {weight_origin[0] - shifted_paths_x_min:.3f} mm")

        if not y_ok:
            if shifted_paths_y_max > weight_bounds_max[1]:
                print(f"       Y exceeds upper bound by {shifted_paths_y_max - weight_bounds_max[1]:.3f} mm")
            if shifted_paths_y_min < weight_origin[1]:
                print(f"       Y below lower bound by {weight_origin[1] - shifted_paths_y_min:.3f} mm")

        if not z_ok:
            if shifted_paths_z_max > weight_bounds_max[2]:
                print(f"       Z exceeds upper bound by {shifted_paths_z_max - weight_bounds_max[2]:.3f} mm")
            if shifted_paths_z_min < weight_origin[2]:
                print(f"       Z below lower bound by {weight_origin[2] - shifted_paths_z_min:.3f} mm")

print("\n" + "="*70)
print("DIAGNOSIS SUMMARY")
print("="*70)

if all_within_bounds:
    print("✓ All shifted paths are within weighting potential bounds.")
    print("The error may be due to a different issue (e.g., grid vs physical coordinates).")
else:
    print("✗ Some shifted paths are OUT OF BOUNDS!")
    print("\nPOSSIBLE SOLUTIONS:")
    print("  1. Extend the weighting potential domain to cover all shifted paths")
    print("  2. Adjust the Y shift value (currently 1.45 mm)")
    print("  3. Reduce the number of strips")
    print("  4. Limit drift paths to stay within bounds")
    print("\nRECOMMENDATION:")
    print("  Check the Z dimension mismatch:")
    print(f"    - Drift domain uses Z up to ~210 mm")
    print(f"    - Extended weighting only covers Z up to {weight_bounds_max[2]:.1f} mm")
    print("  The weighting potential needs to cover the full drift region.")

print("="*70)
