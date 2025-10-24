#!/usr/bin/env python
'''
Collect various generators.

These simply combine generator functions into a common namespace.

See gen() in __main__
'''


from .gen_sandh import generator as sandh
from .gen_sandh2d import generator as sandh2d

from .gen_pcb_quarter import generator as pcb_quarter
from .gen_pcb_2Dstrips import generator as pcb_2D
from .gen_pcb_3Dstrips import generator as pcb_3D

from .gen_pcb_quarter_30deg import generator as pcb_quarter_30deg
from .gen_pcb_2Dstrips_30deg import generator as pcb_2D_30deg
from .gen_pcb_3Dstrips_30deg import generator as pcb_3D_30deg

from .gen_pcb_quarter_90deg import generator as pcb_quarter_90deg
from .gen_pcb_2Dstrips_90deg import generator as pcb_2D_90deg
from .gen_pcb_3Dstrips_90deg import generator as pcb_3D_90deg

from .gen_pcb_pixel_with_grid import generator as pcb_pixel_with_grid
from .gen_pcb_drift_pixel_with_grid import generator as pcb_drift_pixel_with_grid

from .gen_pcb_pixel_with_grid_dense import generator as pcb_pixel_with_grid_dense
from .gen_pcb_drift_pixel_with_grid_dense import generator as pcb_drift_pixel_with_grid_dense


