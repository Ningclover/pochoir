#!/usr/bin/env python3
'''
Info about liquid argon
'''

import math
from . import units
import numpy

def mobility_function(Emag, Temperature = 89*units.Kelvin):
    '''
    Return the mobility for the given magnitude of the electric field
    Emag in system-of-units [voltage]/[distance] and Temperature is in
    units of [temperature].  The mobility is returned in
    system-of-units [distance^2]/[time]/[volage].
    '''

    # put into explicit units to match formula
    
    Emag = Emag /(units.kV/units.cm)
    Trel = Temperature / (89*units.Kelvin)
    #print ('Emag:', Emag)

    # from https://lar.bnl.gov/properties/trans.html
    a0=551.6#*units.cm**2/(units.second)                    # cm2/sec
    # note, this is the adjusted value:
    a1=7158.3#*units.cm**2/(units.second*units.kV)                   # cm2/sec/kV
    a2=4440.43#*units.cm**2/(units.second*math.pow(units.kV,3.0/2.0))                   # cm2/sec/kV^3/2
    a3=4.29#*units.cm**2/(units.second*math.pow(units.kV,5.0/2.0))                      # cm2/sec/kV^5/2
    a4=43.63#*units.cm**2/(units.second*math.pow(units.kV,2.0))                     # cm2/sec/kV^2
    a5=0.2053#*units.cm**2/(units.second*math.pow(units.kV,3.0))                    # cm2/sec/kV^3
    e2 = Emag*Emag
    e3 = Emag*e2
    e5 = e2*e3
    e52 = math.sqrt(e5)
    e32 = math.sqrt(e3)

    Trel32 = math.sqrt(Trel*Trel*Trel)

    mu = (a0 + a1*Emag +a2*e32 + a3*e52)
    mu /= (1 + (a1/a0)*Emag + a4*e2 + a5*e3) * Trel32

    #print ('mu:', mu)

    # mu is now in cm2/sec/V, put into system-of-units
    mu *= units.cm*units.cm
    mu /= units.second
    mu /= units.V
    return mu
mobility = numpy.vectorize(mobility_function)

def longitudanal_diffusion(Emag, Temperature = 89*units.Kelvin):
    '''
    Return DL
    '''

    # put into explicit units to match formula
    
    Emag = Emag /(units.kV/units.cm)
    Trel = Temperature / (89*units.Kelvin)
    T1 = Temperature / (87*units.Kelvin)
    #print ('Emag:', Emag)

    # from https://lar.bnl.gov/properties/trans.html
    a0=551.6#*units.cm**2/(units.second)                    # cm2/sec
    # note, this is the adjusted value:
    a1=7158.3#*units.cm**2/(units.second*units.kV)                   # cm2/sec/kV
    a2=4440.43#*units.cm**2/(units.second*math.pow(units.kV,3.0/2.0))                   # cm2/sec/kV^3/2
    a3=4.29#*units.cm**2/(units.second*math.pow(units.kV,5.0/2.0))                      # cm2/sec/kV^5/2
    a4=43.63#*units.cm**2/(units.second*math.pow(units.kV,2.0))                     # cm2/sec/kV^2
    a5=0.2053#*units.cm**2/(units.second*math.pow(units.kV,3.0))                    # cm2/sec/kV^3
    b0=0.0075
    b1=742.9
    b2=3269.6
    b3=31678.2
    e2 = Emag*Emag
    e3 = Emag*e2
    e5 = e2*e3
    e52 = math.sqrt(e5)
    e32 = math.sqrt(e3)

    Trel32 = math.sqrt(Trel*Trel*Trel)

    f = (a0 + a1*Emag +a2*e32 + a3*e52)
    g = (1 + (a1/a0)*Emag + a4*e2 + a5*e3)
    mu = f/(g*Trel)
    eps = (b0+b1*Emag+b2*e2)*T1
    eps/= (1+(b1/b0)*Emag+b3*e2)
    
    DL = mu*eps

    #print ('mu:', mu)

    #DL is now in cm2/sec, put into system-of-units
    DL *= units.cm*units.cm
    DL /= units.second
    return DL
diff_longit = numpy.vectorize(longitudanal_diffusion)


def transverse_diffusion(Emag, Temperature = 89*units.Kelvin):
    '''
    Return DT
    '''

    # put into explicit units to match formula
    
    Emag = Emag /(units.kV/units.cm)
    Trel = Temperature / (89*units.Kelvin)
    T1 = Temperature / (87*units.Kelvin)
    #print ('Emag:', Emag)

    # from https://lar.bnl.gov/properties/trans.html
    a0=551.6#*units.cm**2/(units.second)                    # cm2/sec
    # note, this is the adjusted value:
    a1=7158.3#*units.cm**2/(units.second*units.kV)                   # cm2/sec/kV
    a2=4440.43#*units.cm**2/(units.second*math.pow(units.kV,3.0/2.0))                   # cm2/sec/kV^3/2
    a3=4.29#*units.cm**2/(units.second*math.pow(units.kV,5.0/2.0))                      # cm2/sec/kV^5/2
    a4=43.63#*units.cm**2/(units.second*math.pow(units.kV,2.0))                     # cm2/sec/kV^2
    a5=0.2053#*units.cm**2/(units.second*math.pow(units.kV,3.0))                    # cm2/sec/kV^3
    b0=0.0075
    b1=742.9
    b2=3269.6
    b3=31678.2
    e2 = Emag*Emag
    e3 = Emag*e2
    e5 = e2*e3
    e52 = math.sqrt(e5)
    e32 = math.sqrt(e3)

    Trel32 = math.sqrt(Trel*Trel*Trel)

    f = (a0 + a1*Emag +a2*e32 + a3*e52)
    f_der = (a1+3*a2*math.sqrt(Emag)/2+5*a3*e32/2)
    g = (1 + (a1/a0)*Emag + a4*e2 + a5*e3)
    g_der = (a1/a0) + 2*a4*Emag + 3*a5*e2
    
    mu_der = (f_der*g-f*g_der)/(Trel*g**2)
    mu = f/(g*Trel)
    eps = (b0+b1*Emag+b2*e2)*T1
    eps/= (1+(b1/b0)*Emag+b3*e2)
    
    DL = mu*eps
    #print ('mu:', mu)
    DT = DL/(1+mu_der*Emag/mu)
    # DT is now in cm2/sec, put into system-of-units
    DT *= units.cm*units.cm
    DT /= units.second
    return DT
diff_tran = numpy.vectorize(transverse_diffusion)
