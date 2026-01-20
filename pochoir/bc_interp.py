#!/usr/bin/env python3

import numpy

# fixme: this can come from arrays.rgi()
from scipy.interpolate import RegularGridInterpolator as RGI

def interp(sol2D, arr3D, barr3D, dom2D,dom3D, xcoord):

    points = list()
    for num, spacing, origin in zip(dom2D.shape, dom2D.spacing, dom2D.origin):
        start = origin
        stop  = origin + num * spacing
        stop_f = float("{:.2f}".format(stop))
        spacing_f = float("{:.2f}".format(spacing))
        rang = numpy.arange(start, stop_f, spacing_f)
        points.append(rang)
        #points.append(numpy.arange(start, stop, spacing))
    
    points.insert(1,numpy.arange(dom3D.origin[1],float("{:.2f}".format(dom3D.origin[1]+(dom3D.shape[1])*dom3D.spacing[1])),dom3D.spacing[1]))
    
    shape2D_ext = (dom2D.shape[0],dom3D.shape[1],dom2D.shape[1])
    sol2D_ext = numpy.zeros(shape2D_ext)
    for j in range(dom3D.shape[1]):
        sol2D_ext[:,j,:]=sol2D
        
    func_interp = RGI(points, sol2D_ext)

    barr3D[0,:,:]=1
    barr3D[-1,:,:]=1

    points3D_x = numpy.array([dom2D.spacing[0]*dom2D.shape[0]/2-xcoord,dom2D.spacing[0]*dom2D.shape[0]/2+xcoord])
    points3D_z = numpy.arange(dom3D.origin[2], dom3D.origin[2]+(dom3D.shape[2])*dom3D.spacing[2], dom3D.spacing[2])
    points3D_y = numpy.arange(dom3D.origin[1], float("{:.2f}".format(dom3D.origin[1]+(dom3D.shape[1])*dom3D.spacing[1])), dom3D.spacing[1])
    print(points3D_x,points3D_x.shape,points3D_y.shape,points3D_z.shape)
    #this part probably can be done faster
    for j in range(dom3D.shape[1]):
            points3D_i = list()
            points3D_f = list()
            for z in points3D_z:
                points3D_i.append(numpy.array([points3D_x[0],points3D_y[j],z]))
                points3D_f.append(numpy.array([points3D_x[1],points3D_y[j],z]))
            arr3D[0,j,:]=func_interp(points3D_i)
            arr3D[-1,j,:]=func_interp(points3D_f)
    #Need to add 2D as a boundary at Z=100mm to make "faster" calculations
    for j in range(dom3D.shape[1]):
        arr3D[:,j,-1]=sol2D[532:532*2,1100]
    barr3D[:,:,-1]=1
    # print(arr3D.shape)
    

    return arr3D,barr3D
