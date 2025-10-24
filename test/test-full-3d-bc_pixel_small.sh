#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


## Domains ##
do_domain () {
    local name=$1 ; shift
    local shape=$1; shift
    local spacing=$1; shift

    want domain/$name \
         pochoir domain --domain domain/$name \
         --shape=$shape --spacing $spacing
}
do_domain drift3d  38,38,1500  '0.1*mm'

# fixme: these weight* identifiers need to split up for N planes.
do_domain weight2d 2142,4200   '0.05*mm'
do_domain weight3d 190,190,1500 '0.1*mm'


## Initial/Boundary Value Arrays ##

do_gen_drift () {
    local name=$1 ; shift
    local geom=$1; shift
    local gen="pcb_drift_pixel_with_grid"
    local cfg="example_gen_pcb_drift_pixel_with_grid_small.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}

do_gen_drift drift3d asd

do_gen_weight () {
    local name=$1 ; shift
    local geom=$1; shift
    local gen="pcb_pixel_with_grid"
    local cfg="example_gen_pixel_with_grid_small.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}

do_gen_weight weight3d asd




