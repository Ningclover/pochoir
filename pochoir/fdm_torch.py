#!/usr/bin/env python3
'''
Apply FDM solution to solve Laplace boundary value problem with torch.
'''

import numpy
import torch
from .arrays import core_slices1

from .fdm_generic import edge_condition, stencil

    
def set_core1(dst, src, core):
    dst[core] = src

def set_core2(dst, src, core):
    dst[core] = src

def solve(iarr, barr, periodic, prec, epoch, nepochs):
    '''
    Solve boundary value problem

    Return (arr, err)

        - iarr gives array of initial values

        - barr gives bool array where True indicates value at that
          index is boundary (imutable).

        - periodic is list of Boolean.  If true, the corresponding
          dimension is periodic, else it is fixed.

        - epoch is number of iteration per precision check

        - nepochs limits the number of epochs

    Returned arrays "arr" is like iarr with updated solution including
    fixed boundary value elements.  "err" is difference between last
    and penultimate iteration.
    '''

    err = None

    bi_core = torch.tensor(iarr*barr, requires_grad=False)
    mutable_core = torch.tensor(numpy.invert(barr.astype(bool)), requires_grad=False)
    tmp_core = torch.zeros(iarr.shape, requires_grad=False)

    barr_pad = torch.tensor(numpy.pad(barr, 1), requires_grad=False)
    iarr_pad = torch.tensor(numpy.pad(iarr, 1), requires_grad=False)
    core = core_slices1(iarr_pad)

    # Get indices of fixed boundary values and values themselves

    prev = None
    check_interval = 100  # Measure convergence over last 100 iterations

    for iepoch in range(nepochs):
        print(f'epoch: {iepoch}/{nepochs} x {epoch}')
        max_change_in_epoch = 0.0

        for istep in range(epoch):
            # Save state 100 iterations before the end
            if epoch - istep == check_interval:
                prev = iarr_pad[core].clone().detach().requires_grad_(False)

            stencil(iarr_pad, tmp_core)
            iarr_pad[core] = bi_core + mutable_core*tmp_core
            edge_condition(iarr_pad, *periodic)

        # Compute change over last 100 iterations
        if prev is not None:
            err = iarr_pad[core] - prev
            maxerr = torch.max(torch.abs(err))
            meanerr = torch.mean(torch.abs(err))
            max_change_in_epoch = maxerr
            print(f'  last {check_interval} iters - maxerr: {maxerr:.6e}, meanerr: {meanerr:.6e}')

            if prec and maxerr < prec * check_interval:
                print(f'fdm reach max precision: {prec * check_interval} > {maxerr} (over {check_interval} iters)')
                return (iarr_pad[core], err)
        else:
            print(f'  (convergence check not available yet)')

    print(f'fdm reach max epoch {epoch} x {nepochs}, last prec {prec * check_interval} < {max_change_in_epoch}')
    if prev is not None:
        return (iarr_pad[core], err)
    else:
        # Fallback for very small epochs
        return (iarr_pad[core], torch.zeros_like(iarr_pad[core]))

