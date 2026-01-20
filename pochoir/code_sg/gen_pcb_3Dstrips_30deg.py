#!/usr/bin/env python3

import numpy
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

from .gen_pcb_quarter_30deg import draw_pcb_plane as draw_quarter

def mirror_arr_yaxis(arr):
    result = numpy.empty_like(arr)
    result[:,::-1]=arr[:,:]
    return result
    
def mirror_arr_xaxis(arr):
    result = numpy.empty_like(arr)
    result[::-1,:]=arr[:,:]
    return result

def draw_3Dstrips(arr,barr,qbarr_4,Nstrips,pcb_low_edge,pcb_width,plane):

    shape = (len(qbarr_4),len(qbarr_4[0]))
    qbarr_1 = mirror_arr_yaxis(qbarr_4)
    for v in range(0,2):
        for s in range(0,3*Nstrips,3):
            if s%2 == 0:
                barr[s*shape[0]:(s+1)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[s*shape[0]:(s+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
            if s%2!=0:
                barr[s*shape[0]:(s+1)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[s*shape[0]:(s+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
            #at the moment plane 1 is ind2 and plane 2 is ind 1 follow coll->ind2->ind1->shield
            if plane==1 and v==1:
                half = int((Nstrips-1)*3/2)
                arr[half*shape[0]:(half+1)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                arr[half*shape[0]:(half+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],0:shape[1],pcb_low_edge+pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],0:shape[1],pcb_low_edge+pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
            if plane==2 and v==2:
                half = int((Nstrips-1)*3/2)
                arr[half*shape[0]:(half+1)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[half*shape[0]:(half+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]
    
    pcb_low_edge = pcb_low_edge+pcb_width+200
    for v in range(0,2):
        for s in range(0,3*Nstrips,3):
            if s%2 == 0:
                barr[s*shape[0]:(s+1)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[s*shape[0]:(s+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
            if s%2!=0:
                barr[s*shape[0]:(s+1)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[s*shape[0]:(s+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
                barr[(s+1)*shape[0]:(s+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],0:shape[1],pcb_low_edge+v*pcb_width] = qbarr_1[:,:,0]
                barr[(s+2)*shape[0]:(s+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+v*pcb_width] = qbarr_4[:,:,0]
            #at the moment plane 1 is ind2 and plane 2 is ind 1 follow coll->ind2->ind1->shield
            if plane==2 and v==0:
                half = int((Nstrips-1)*3/2)
                arr[half*shape[0]:(half+1)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[half*shape[0]:(half+1)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]
                arr[(half+1)*shape[0]:(half+2)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],0:shape[1],pcb_low_edge+2*pcb_width] = qbarr_1[:,:,0]
                arr[(half+2)*shape[0]:(half+3)*shape[0],shape[1]:2*shape[1],pcb_low_edge+2*pcb_width] = qbarr_4[:,:,0]


def generator(dom, cfg):
    
    plane = cfg['plane']
    r1 = int(round(cfg['FirstHoleRadius']/dom.spacing[0])-1)
    r2 = int(round(cfg['SecondHoleRadius']/dom.spacing[0])-1)
    pcb_width = int(cfg['PcbWidth']/dom.spacing[0])
    pcb_low_edge = int(cfg['PcbLowEdgePosition']/dom.spacing[0])
    Nstrips = cfg['Nstrips']
    
    shape_q = (int(round(cfg['QuarterDimX']/dom.spacing[0])),int(round(cfg['QuarterDimY']/dom.spacing[0])),1)
    
    arr = numpy.zeros(dom.shape)
    barr = numpy.zeros(dom.shape)
    
    #define quarter-strip
    qbarr_4 = numpy.ones(shape_q)
    draw_quarter(shape_q,qbarr_4,0,r1,r2,0,(0,1))
    
    #draw full pattern
    draw_3Dstrips(arr,barr,qbarr_4,Nstrips,pcb_low_edge,pcb_width,plane)
    
    barr[:,:,0]=1
    return arr,barr
