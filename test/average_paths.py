#!/usr/bin/env python3
"""
Average electron paths from pochoir induce output to format for convertfr()

This script takes the induced current data (132 paths on a grid) and averages
them into the format expected by convertfr(): nstrips × npaths organized array.
"""

import numpy as np
import json
import sys
from pathlib import Path

def average_paths_for_convertfr(current_dir, config_file, output_file,
                                 strip_direction='y', npaths=6, max_ticks=1325):
    """
    Average induced current paths into convertfr format.

    Parameters:
    -----------
    current_dir : str
        Directory containing induced_current_*.npz files
    config_file : str
        JSON config file with Nstrips parameter
    output_file : str
        Output .npz file path
    strip_direction : str
        'x' or 'y' - which axis runs along the strips
    npaths : int
        Number of paths per strip (typically 6)
    max_ticks : int
        Maximum number of time samples to keep (convertfr uses 1325)
    """

    # Load configuration
    with open(config_file, 'r') as f:
        cfg = json.load(f)
    nstrips = cfg['Nstrips']

    # Load starting positions and current data
    starts = np.load(Path(current_dir) / 'induced_current_avg_ind.npz',
                     allow_pickle=True)

    # Try to find the starts file
    starts_file = Path(current_dir).parent.parent / 'starts' / 'drift3d.npz'
    if not starts_file.exists():
        # Try alternative path
        starts_file = Path(current_dir).parent / 'starts' / 'drift3d.npz'

    positions = np.load(starts_file)['drift3d']

    # Load current data
    current_data = np.load(Path(current_dir) / 'induced_current_avg_ind.npz')['induced_current_avg_ind']

    npaths_total = current_data.shape[0]
    nticks = min(current_data.shape[1], max_ticks)

    print(f"Loaded {npaths_total} paths with {current_data.shape[1]} time samples")
    print(f"Will use first {nticks} time samples")
    print(f"Position data shape: {positions.shape}")

    # Determine which axis is the strip direction (transverse to wire)
    # and which is along the strip
    if strip_direction.lower() == 'y':
        strip_axis = 1  # Y is transverse (across strips)
        along_axis = 0  # X is along strip
    else:
        strip_axis = 0  # X is transverse (across strips)
        along_axis = 1  # Y is along strip

    strip_coords = positions[:, strip_axis]
    along_coords = positions[:, along_axis]

    print(f"\nStrip direction (transverse): axis {strip_axis}")
    print(f"  Range: [{np.min(strip_coords):.3f}, {np.max(strip_coords):.3f}]")
    print(f"Along-strip direction: axis {along_axis}")
    print(f"  Range: [{np.min(along_coords):.3f}, {np.max(along_coords):.3f}]")

    # Define strip boundaries
    strip_min = np.min(strip_coords)
    strip_max = np.max(strip_coords)
    strip_edges = np.linspace(strip_min, strip_max, nstrips + 1)

    print(f"\nDividing into {nstrips} strips:")
    for i in range(nstrips):
        print(f"  Strip {i}: [{strip_edges[i]:.3f}, {strip_edges[i+1]:.3f}]")

    # Initialize output array
    averaged_currents = []
    positions_out = []

    # Process each strip
    for istrip in range(nstrips):
        # Find paths in this strip
        in_strip = (strip_coords >= strip_edges[istrip]) & \
                   (strip_coords <= strip_edges[istrip + 1])

        n_in_strip = np.sum(in_strip)
        print(f"\nStrip {istrip}: {n_in_strip} paths")

        if n_in_strip == 0:
            print(f"  WARNING: No paths in strip {istrip}, using zeros")
            for ipath in range(npaths):
                averaged_currents.append(np.zeros(nticks))
                pos = strip_edges[istrip] + (strip_edges[istrip+1] - strip_edges[istrip]) * (ipath + 0.5) / npaths
                positions_out.append(pos)
            continue

        strip_currents = current_data[in_strip, :nticks]
        strip_positions = along_coords[in_strip]

        # Sort by along-strip position
        sort_idx = np.argsort(strip_positions)
        strip_currents = strip_currents[sort_idx]
        strip_positions = strip_positions[sort_idx]

        # Divide into npaths bins along the strip
        along_min = np.min(strip_positions)
        along_max = np.max(strip_positions)
        path_edges = np.linspace(along_min, along_max, npaths + 1)

        for ipath in range(npaths):
            # Find paths in this bin
            in_bin = (strip_positions >= path_edges[ipath]) & \
                     (strip_positions <= path_edges[ipath + 1])

            n_in_bin = np.sum(in_bin)

            if n_in_bin > 0:
                # Average all paths in this bin
                avg_current = np.mean(strip_currents[in_bin], axis=0)
                print(f"  Path {ipath}: averaged {n_in_bin} paths")
            else:
                # No paths in this bin - use nearest neighbor or interpolate
                print(f"  Path {ipath}: no paths, using nearest")
                # Find nearest path
                bin_center = (path_edges[ipath] + path_edges[ipath + 1]) / 2
                nearest_idx = np.argmin(np.abs(strip_positions - bin_center))
                avg_current = strip_currents[nearest_idx]

            averaged_currents.append(avg_current)

            # Record position (transverse position)
            pos = (strip_edges[istrip] + strip_edges[istrip + 1]) / 2
            positions_out.append(pos)

    averaged_currents = np.array(averaged_currents)
    positions_out = np.array(positions_out)

    print(f"\n{'='*60}")
    print(f"Output shape: {averaged_currents.shape}")
    print(f"Expected shape: ({nstrips * npaths}, {nticks})")
    print(f"Positions shape: {positions_out.shape}")

    # Save output
    np.savez(output_file,
             current=averaged_currents,
             positions=positions_out)

    print(f"\nSaved to: {output_file}")
    print(f"  Keys: 'current' (shape {averaged_currents.shape}), 'positions' (shape {positions_out.shape})")

    return averaged_currents, positions_out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python average_paths.py [config.json] [--strip-dir x|y] [--npaths N]")
        print("\nExample:")
        print("  python average_paths.py example_gen_pcb_3D_config.json --strip-dir y --npaths 6")
        sys.exit(1)

    config_file = sys.argv[1]

    # Parse optional arguments
    strip_direction = 'y'
    npaths = 6

    for i, arg in enumerate(sys.argv[2:], 2):
        if arg == '--strip-dir' and i + 1 < len(sys.argv):
            strip_direction = sys.argv[i + 1]
        elif arg == '--npaths' and i + 1 < len(sys.argv):
            npaths = int(sys.argv[i + 1])

    # Assume current data is in ./store/current/
    current_dir = Path(__file__).parent / 'store' / 'current'
    output_file = Path(__file__).parent / 'store' / 'current' / 'averaged_for_convertfr.npz'

    print("="*60)
    print("Averaging paths for convertfr()")
    print("="*60)
    print(f"Config file: {config_file}")
    print(f"Current dir: {current_dir}")
    print(f"Output file: {output_file}")
    print(f"Strip direction: {strip_direction}")
    print(f"Paths per strip: {npaths}")
    print("="*60)

    average_paths_for_convertfr(
        current_dir=str(current_dir),
        config_file=config_file,
        output_file=str(output_file),
        strip_direction=strip_direction,
        npaths=npaths
    )
