#!/usr/bin/env python3

import numpy

def draw_plane(arr,z,potential):
    arr[:,z]=potential
    
def draw_strip(dom,holeWidth,betweenHoles,Nstrips,potential,cfg):
    
    spacing = dom.spacing[0]
    strip=numpy.zeros(int(dom.shape[0]/Nstrips))
    dH = int(round(holeWidth/2))
    dB = int(betweenHoles)
    if cfg==0:
        strip[0:dH]=0
        strip[dH:dH+2*dB]=potential
        strip[dH+2*dB:2*dH+2*dB]=0
    if cfg==1:
        strip[0:dB]=potential
        strip[dB:dB+2*dH]=0
        strip[dB+2*dH:2*dB+2*dH]=potential
    return strip

def draw_hole_pattern(arr,barr,dom,z,widthX,widthZ,holeWidth,betweenHoles,Nstrips,active):
    
    shape = dom.shape
    spacing = dom.spacing[0]
    betweenHoles = int(round(betweenHoles/spacing))
    holeWidth = int(round(holeWidth/spacing))
    dX=int(round(widthX/spacing))
    print(z,betweenHoles,holeWidth,dX)
    strip_p1_0 = draw_strip(dom,holeWidth,betweenHoles,Nstrips,1,0)
    strip_p1_1 = draw_strip(dom,holeWidth,betweenHoles,Nstrips,1,1)
    for x in range(0,Nstrips):
        #if x%2==0:
        barr[x*dX:(x+1)*dX,z]=strip_p1_0
        if x==(Nstrips-1)/2 and active==1:
            arr[x*dX:(x+1)*dX,z]=strip_p1_0
    

def generator(dom, cfg):
    """
    need to pass strip width in X and Z, holewidth in mm and configuration of 2D plane
    conf=0 with quaterholes on a sides and dimHole providing the dim of the left hole, conf=1 with hole in the middle
    """
    arr = numpy.zeros(dom.shape)
    barr = numpy.zeros(dom.shape)
    print("2D_90deg")
    plane = cfg['plane'];  # check which plane to set to 1V (coll/ind)
    conf= cfg['config']    # 2d view configuration
    widthX = cfg['StripWidthX'] #strip width in X
    widthZ = cfg['StripWidthZ'] # strip width in Z
    positionZ = cfg['LowEdgePosition'] # lowes position of the strip in Z in mm
    holeWidth = cfg['HoleDiameter']    # hole diameter in the strip
    betweenHoles = cfg['BetweenHoles']
    Nstrips = cfg['Nstrips']           # total number of strips
    ground_plane = int(cfg['GroundPosition']/dom.spacing[1])
        
    shape = dom.shape
    spacing = dom.spacing[0]
    z_c=int(round(positionZ/spacing))
    z_i2=int(round((positionZ+widthZ)/spacing))
    z_i1=int(round((positionZ+widthZ+10)/spacing))
    z_sh=int(round((positionZ+2*widthZ+10)/spacing))
    
    #at the moment plane 1 is ind2 and plane 2 is ind 1 follow coll->ind2->ind1
    draw_hole_pattern(arr,barr,dom,z_c,widthX,widthZ,holeWidth,betweenHoles,Nstrips,0)
    draw_hole_pattern(arr,barr,dom,z_i2,widthX,widthZ,holeWidth,betweenHoles,Nstrips,0)
    draw_hole_pattern(arr,barr,dom,z_i1,widthX,widthZ,holeWidth,betweenHoles,Nstrips,0)
    draw_hole_pattern(arr,barr,dom,z_sh,widthX,widthZ,holeWidth,betweenHoles,Nstrips,0)
    
    #This is only for collection
    draw_hole_pattern(arr,barr,dom,z_c,widthX,widthZ,holeWidth,betweenHoles,Nstrips,1)

    barr[:,ground_plane] = 1 
    barr[:,0]=1
    barr[0,:]=1
    barr[-1,:]=1
    #arr[:,0]=0
    #arr[:,-1]=0
    #draw_plane(barr,shape[1]-1,1)

    return arr,barr
