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
do_domain weight2d_u 1607,2100   '0.1*mm'
do_domain weight3d_u 536,30,2100 '0.1*mm'
do_domain weight2d_v 1607,2100   '0.1*mm'
do_domain weight3d_v 536,30,2100 '0.1*mm'
do_domain weight2d_w 1071,2100   '0.1*mm'
do_domain weight3d_w 357,30,2100 '0.1*mm'


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
do_gen_uv weight2d_u 2D _u
do_gen_uv weight3d_u 3D _u
do_gen_uv weight2d_v 2D _v
do_gen_uv weight3d_v 3D _v

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

# do_fdm drift3d  20      200000      0.00000005     fix,fix,fix
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

# Then call it:
# do_fdm_resume drift3d  200  2000000  0.00000001  fix,fix,fix

# stripX = 3*QuarterDimX # u/v strip
# xcoord = (Number of ACTIVE sensing strips) × (stripX) / 2

want initial/weight3dfull_u \
     pochoir bc-interp --xcoord '26.78*mm' \
     --initial initial/weight3dfull_u --boundary boundary/weight3dfull_u \
     --initial3d initial/weight3d_u --boundary3d boundary/weight3d_u \
     --potential2d potential/weight2d_u

want initial/weight3dfull_v \
     pochoir bc-interp --xcoord '26.78*mm' \
     --initial initial/weight3dfull_v --boundary boundary/weight3dfull_v \
     --initial3d initial/weight3d_v --boundary3d boundary/weight3d_v \
     --potential2d potential/weight2d_v

# stripX = 2*QuarterDimX # w strip
# xcoord = (Number of ACTIVE sensing strips) × (stripX) / 2

want initial/weight3dfull_w \
     pochoir bc-interp --xcoord '17.85*mm' \
     --initial initial/weight3dfull_w --boundary boundary/weight3dfull_w \
     --initial3d initial/weight3d_w --boundary3d boundary/weight3d_w \
     --potential2d potential/weight2d_w

do_fdm weight3dfull_u 10      9000      0.00001     fix,fix,fix
# do_fdm weight3dfull_v 10      9000      0.00001     fix,fix,fix
# do_fdm weight3dfull_w 10      9000      0.00001     fix,fix,fix


want velocity/drift3d \
     pochoir velo --temperature '89*K' \
     --potential potential/drift3d \
     --velocity velocity/drift3d


# want starts/drift3d \
#     pochoir starts --starts starts/drift3d \
#      '0.05*mm,0.05*mm,198*mm' 

want starts/drift3d \
    pochoir starts --starts starts/drift3d \
     '0.05*mm,0.05*mm,198*mm' '0.05*mm,0.19*mm,198*mm' '0.05*mm,0.33*mm,198*mm' '0.05*mm,0.47*mm,198*mm' '0.05*mm,0.61*mm,198*mm' '0.05*mm,0.75*mm,198*mm' '0.05*mm,0.89*mm,198*mm' '0.05*mm,1.03*mm,198*mm' '0.05*mm,1.17*mm,198*mm' '0.05*mm,1.31*mm,198*mm' \
     '0.81*mm,0.05*mm,198*mm' '0.81*mm,0.19*mm,198*mm' '0.81*mm,0.33*mm,198*mm' '0.81*mm,0.47*mm,198*mm' '0.81*mm,0.61*mm,198*mm' '0.81*mm,0.75*mm,198*mm' '0.81*mm,0.89*mm,198*mm' '0.81*mm,1.03*mm,198*mm' '0.81*mm,1.17*mm,198*mm' '0.81*mm,1.31*mm,198*mm' \
     '1.56*mm,0.05*mm,198*mm' '1.56*mm,0.19*mm,198*mm' '1.56*mm,0.33*mm,198*mm' '1.56*mm,0.47*mm,198*mm' '1.56*mm,0.61*mm,198*mm' '1.56*mm,0.75*mm,198*mm' '1.56*mm,0.89*mm,198*mm' '1.56*mm,1.03*mm,198*mm' '1.56*mm,1.17*mm,198*mm' '1.56*mm,1.31*mm,198*mm' \
      '2.32*mm,0.05*mm,198*mm' '2.32*mm,0.19*mm,198*mm' '2.32*mm,0.33*mm,198*mm' '2.32*mm,0.47*mm,198*mm' '2.32*mm,0.61*mm,198*mm' '2.32*mm,0.75*mm,198*mm' '2.32*mm,0.89*mm,198*mm' '2.32*mm,1.03*mm,198*mm' '2.32*mm,1.17*mm,198*mm' '2.32*mm,1.31*mm,198*mm'  \
      '0.52*mm,0.05*mm,198*mm' '0.52*mm,0.19*mm,198*mm' '0.52*mm,0.33*mm,198*mm' '0.52*mm,0.47*mm,198*mm' '0.52*mm,0.61*mm,198*mm' '0.52*mm,0.75*mm,198*mm' '0.52*mm,0.89*mm,198*mm' '0.52*mm,1.03*mm,198*mm' '0.52*mm,1.17*mm,198*mm' '0.52*mm,1.31*mm,198*mm'  \
      '1.28*mm,0.05*mm,198*mm' '1.28*mm,0.19*mm,198*mm' '1.28*mm,0.33*mm,198*mm' '1.28*mm,0.47*mm,198*mm' '1.28*mm,0.61*mm,198*mm' '1.28*mm,0.75*mm,198*mm' '1.28*mm,0.89*mm,198*mm' '1.28*mm,1.03*mm,198*mm' '1.28*mm,1.17*mm,198*mm' '1.28*mm,1.31*mm,198*mm'  \
     '0.05*mm,0.05*mm,198*mm' '0.05*mm,0.19*mm,198*mm' '0.05*mm,0.33*mm,198*mm' '0.05*mm,0.47*mm,198*mm' '0.05*mm,0.61*mm,198*mm' '0.05*mm,0.75*mm,198*mm' '0.05*mm,0.89*mm,198*mm' '0.05*mm,1.03*mm,198*mm' '0.05*mm,1.17*mm,198*mm' '0.05*mm,1.31*mm,198*mm' '0.81*mm,0.05*mm,198*mm' '0.81*mm,0.19*mm,198*mm' '0.81*mm,0.33*mm,198*mm' '0.81*mm,0.47*mm,198*mm' '0.81*mm,0.61*mm,198*mm' '0.81*mm,0.75*mm,198*mm' '0.81*mm,0.89*mm,198*mm' '0.81*mm,1.03*mm,198*mm' '0.81*mm,1.17*mm,198*mm' '0.81*mm,1.31*mm,198*mm' '1.56*mm,0.05*mm,198*mm' '1.56*mm,0.19*mm,198*mm' '1.56*mm,0.33*mm,198*mm' '1.56*mm,0.47*mm,198*mm' '1.56*mm,0.61*mm,198*mm' '1.56*mm,0.75*mm,198*mm' '1.56*mm,0.89*mm,198*mm' '1.56*mm,1.03*mm,198*mm' '1.56*mm,1.17*mm,198*mm' '1.56*mm,1.31*mm,198*mm' '2.32*mm,0.05*mm,198*mm' '2.32*mm,0.19*mm,198*mm' '2.32*mm,0.33*mm,198*mm' '2.32*mm,0.47*mm,198*mm' '2.32*mm,0.61*mm,198*mm' '2.32*mm,0.75*mm,198*mm' '2.32*mm,0.89*mm,198*mm' '2.32*mm,1.03*mm,198*mm' '2.32*mm,1.17*mm,198*mm' '2.32*mm,1.31*mm,198*mm' '0.52*mm,0.05*mm,198*mm' '0.52*mm,0.19*mm,198*mm' '0.52*mm,0.33*mm,198*mm' '0.52*mm,0.47*mm,198*mm' '0.52*mm,0.61*mm,198*mm' '0.52*mm,0.75*mm,198*mm' '0.52*mm,0.89*mm,198*mm' '0.52*mm,1.03*mm,198*mm' '0.52*mm,1.17*mm,198*mm' '0.52*mm,1.31*mm,198*mm' '1.28*mm,0.05*mm,198*mm' '1.28*mm,0.19*mm,198*mm' '1.28*mm,0.33*mm,198*mm' '1.28*mm,0.47*mm,198*mm' '1.28*mm,0.61*mm,198*mm' '1.28*mm,0.75*mm,198*mm' '1.28*mm,0.89*mm,198*mm' '1.28*mm,1.03*mm,198*mm' '1.28*mm,1.17*mm,198*mm' '1.28*mm,1.31*mm,198*mm' 


want paths/drift3d \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
    --paths paths/drift3d '0*us,300*us,0.1*us'
     # --paths paths/drift3d '0*us,300*us,0.05*us'


want starts/drift3d_w \
     pochoir starts --starts starts/drift3d_w \
     '0.05*mm,0.05*mm,198.0*mm' '0.05*mm,0.19*mm,198.0*mm' '0.05*mm,0.33*mm,198.0*mm' '0.05*mm,0.47*mm,198.0*mm' '0.05*mm,0.61*mm,198.0*mm' '0.05*mm,0.75*mm,198.0*mm' '0.05*mm,0.89*mm,198.0*mm' '0.05*mm,1.03*mm,198.0*mm' '0.05*mm,1.17*mm,198.0*mm' '0.05*mm,1.31*mm,198.0*mm' \
     '0.51*mm,0.05*mm,198.0*mm' '0.51*mm,0.19*mm,198.0*mm' '0.51*mm,0.33*mm,198.0*mm' '0.51*mm,0.47*mm,198.0*mm' '0.51*mm,0.61*mm,198.0*mm' '0.51*mm,0.75*mm,198.0*mm' '0.51*mm,0.89*mm,198.0*mm' '0.51*mm,1.03*mm,198.0*mm' '0.51*mm,1.17*mm,198.0*mm' '0.51*mm,1.31*mm,198.0*mm' \
     '1.02*mm,0.05*mm,198.0*mm' '1.02*mm,0.19*mm,198.0*mm' '1.02*mm,0.33*mm,198.0*mm' '1.02*mm,0.47*mm,198.0*mm' '1.02*mm,0.61*mm,198.0*mm' '1.02*mm,0.75*mm,198.0*mm' '1.02*mm,0.89*mm,198.0*mm' '1.02*mm,1.03*mm,198.0*mm' '1.02*mm,1.17*mm,198.0*mm' '1.02*mm,1.31*mm,198.0*mm' \
     '1.53*mm,0.05*mm,198.0*mm' '1.53*mm,0.19*mm,198.0*mm' '1.53*mm,0.33*mm,198.0*mm' '1.53*mm,0.47*mm,198.0*mm' '1.53*mm,0.61*mm,198.0*mm' '1.53*mm,0.75*mm,198.0*mm' '1.53*mm,0.89*mm,198.0*mm' '1.53*mm,1.03*mm,198.0*mm' '1.53*mm,1.17*mm,198.0*mm' '1.53*mm,1.31*mm,198.0*mm' \
     '2.04*mm,0.05*mm,198.0*mm' '2.04*mm,0.19*mm,198.0*mm' '2.04*mm,0.33*mm,198.0*mm' '2.04*mm,0.47*mm,198.0*mm' '2.04*mm,0.61*mm,198.0*mm' '2.04*mm,0.75*mm,198.0*mm' '2.04*mm,0.89*mm,198.0*mm' '2.04*mm,1.03*mm,198.0*mm' '2.04*mm,1.17*mm,198.0*mm' '2.04*mm,1.31*mm,198.0*mm' \
     '2.54*mm,0.05*mm,198.0*mm' '2.54*mm,0.19*mm,198.0*mm' '2.54*mm,0.33*mm,198.0*mm' '2.54*mm,0.47*mm,198.0*mm' '2.54*mm,0.61*mm,198.0*mm' '2.54*mm,0.75*mm,198.0*mm' '2.54*mm,0.89*mm,198.0*mm' '2.54*mm,1.03*mm,198.0*mm' '2.54*mm,1.17*mm,198.0*mm' '2.54*mm,1.31*mm,198.0*mm'

want paths/drift3d_w \
     pochoir drift --starts starts/drift3d_w \
     --velocity velocity/drift3d \
    --paths paths/drift3d_w '0*us,300*us,0.1*us'
     # --paths paths/drift3d '0*us,300*us,0.05*us'

# pochoir extendwf -p potential/weight2d_u -P potential/weight3dfull_u -n 10 -o potential/weight3dextend_u
# pochoir extendwf -p potential/weight2d_v -P potential/weight3dfull_v -n 10 -o potential/weight3dextend_v
# pochoir extendwf -p potential/weight2d_w -P potential/weight3dfull_w -n 10 -o potential/weight3dextend_w


# want current/induced_current_avg_ind_u \
#      pochoir induce-30deg --weighting potential/weight3dextend_u \
#      --paths paths/drift3d \
#      --output current/induced_current_avg_ind_u
#      # --nstrips  21
#      # --average 10\
# want current/induced_current_avg_ind_v \
#      pochoir induce-30deg --weighting potential/weight3dextend_v \
#      --paths paths/drift3d \
     # --output current/induced_current_avg_ind_v

want current/induced_current_avg_ind_u \
     pochoir induce-30deg --weighting potential/weight3dextend_u \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind_u\
     --nstrips  21\
     -S paths/weight3dextend_u\
     --average 10

want current/induced_current_avg_ind_v \
     pochoir induce-30deg --weighting potential/weight3dextend_v \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind_v\
     --nstrips 21\
     -S paths/weight3dextend_v\
     --average 10

want current/induced_current_avg_ind_w \
     pochoir induce --weighting potential/weight3dextend_w \
     --paths paths/drift3d_w \
     --output current/induced_current_avg_ind_w\
     --nstrips 21\
     -S paths/weight3dextend_w\
     --average 10

# pochoir convertfr -u current/induced_current_avg_ind_u -v current/induced_current_avg_ind_v -w current/induced_current_avg_ind_w -O current/FR_xn_new.json.bz2 example_convertfr_vd.json

want_file $POCHOIR_STORE/current/FR_xn_new.json.bz2 \
    pochoir convertfr -u current/induced_current_avg_ind_u \
    -v current/induced_current_avg_ind_v \
    -w current/induced_current_avg_ind_w \
    -O $POCHOIR_STORE/current/FR_xn_new.json.bz2 example_convertfr_vd.json

date

