#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh

date

## Domains ##
do_domain () {
    local name=$1 ; shift
    local shape=$1; shift
    local spacing=$1; shift

    want domain/$name \
         pochoir domain --domain domain/$name \
         --shape=$shape --spacing $spacing
}
# do_domain drift3d  51,29,4200  '0.05*mm'
do_domain drift3d  25,15,2100  '0.1*mm'

# fixme: these weight* identifiers need to split up for N planes.
# do_domain weight2d_u 1607,2100   '0.1*mm'
# do_domain weight3d_u 536,30,2100 '0.1*mm'
# do_domain weight2d_v 1607,2100   '0.1*mm'
# do_domain weight3d_v 536,30,2100 '0.1*mm'
# do_domain weight2d_w 1071,2100   '0.1*mm'
# do_domain weight3d_w 357,30,2100 '0.1*mm'


## Initial/Boundary Value Arrays ##
do_gen_uv () {
    local name=$1 ; shift
    local geom=$1; shift
    local plane=$1; shift
    local gen="pcb_${geom}_30deg"
    local cfg="example_gen_pcb_${geom}_config_30deg${plane}.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}
do_gen_uv drift3d quarter "" 
# do_gen_uv weight2d_u 2D _u
# do_gen_uv weight3d_u 3D _u
# do_gen_uv weight2d_v 2D _v
# do_gen_uv weight3d_v 3D _v

do_gen_w () {
    local name=$1 ; shift
    local geom=$1; shift
    local gen="pcb_${geom}_90deg"
    local cfg="example_gen_pcb_${geom}_config.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}

# do_gen_w weight2d_w 2D
# do_gen_w weight3d_w 3D

## Fields
do_fdm () {
    local name=$1 ; shift
    local nepochs=$1 ; shift
    local epoch=$1 ; shift
    local prec=$1 ; shift
    local edges=$1 ; shift

    want potential/$name \
         pochoir fdm \
         --nepochs $nepochs --epoch $epoch --precision $prec \
         --edges $edges \
	 --engine cumba \
         --initial initial/$name --boundary boundary/$name \
         --potential potential/$name \
         --increment increment/$name
}

do_fdm drift3d  200      2000000      0.000001     fix,fix,fix
# do_fdm weight2d_u 20      200000      0.00000005   fix,fix
# do_fdm weight2d_v 20      200000      0.00000005   fix,fix
# do_fdm weight2d_w 20      200000      0.00000005   fix,fix


# Resume FDM from existing potential
# Resume FDM from existing potential (overwrites without checking)
# do_fdm_resume () {
#     local name=$1 ; shift
#     local nepochs=$1 ; shift
#     local epoch=$1 ; shift
#     local prec=$1 ; shift
#     local edges=$1 ; shift

#     # Remove 'want' wrapper to force execution
#     pochoir fdm \
#          --nepochs $nepochs --epoch $epoch --precision $prec \
#          --edges $edges \
#          --engine cumba \
#          --initial potential/$name \
#          --boundary boundary/$name \
#          --potential potential/$name \
#          --increment increment/$name
# }

# # # Then call it:
# do_fdm_resume drift3d  200  2000000  0.000000001  fix,fix,fix


date

