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
#do_domain drift3d  50,29,4200  '0.05*mm'

# fixme: these weight* identifiers need to split up for N planes.
do_domain weight2d 3213,4200   '0.05*mm'
do_domain weight3d 1071,58,1600 '0.05*mm'


## Initial/Boundary Value Arrays ##
do_gen () {
    local name=$1 ; shift
    local geom=$1; shift
    local gen="pcb_${geom}_30deg"
    local cfg="example_gen_pcb_${geom}_config_30deg.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}
#do_gen drift3d quarter
do_gen weight2d 2D
do_gen weight3d 3D




