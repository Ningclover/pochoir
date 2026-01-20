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
# do_domain drift3d  25,17,2100  '0.1*mm'

# fixme: these weight* identifiers need to split up for N planes.
# do_domain weight2d 1596,2100   '0.1*mm'
# do_domain weight3d 532,32,2100 '0.1*mm'


## Initial/Boundary Value Arrays ##
do_gen () {
    local name=$1 ; shift
    local geom=$1; shift
    local gen="pcb_${geom}_30deg"
    local cfg="example_gen_pcb_${geom}_config_30deg_v.json"

    want initial/$name \
         pochoir gen --generator $gen --domain domain/$name \
         --initial initial/$name --boundary boundary/$name \
         $cfg

}
# do_gen drift3d quarter
do_gen weight2d 2D
do_gen weight3d 3D

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
# do_fdm drift3d  20      200000      0.00000002     fix,fix,fix
do_fdm weight2d 20      200000      0.00000002   fix,fix


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


# xcoord = (Number of ACTIVE sensing strips) × (3 × QuarterDimX) / 2

want initial/weight3dfull \
     pochoir bc-interp --xcoord '26.5*mm' \
     --initial initial/weight3dfull --boundary boundary/weight3dfull \
     --initial3d initial/weight3d --boundary3d boundary/weight3d \
     --potential2d potential/weight2d

do_fdm weight3dfull 10      9000      0.00001     fix,fix,fix


# want velocity/drift3d \
#      pochoir velo --temperature '89*K' \
#      --potential potential/drift3d \
#      --velocity velocity/drift3d


# want starts/drift3d \
#     pochoir starts --starts starts/drift3d \
#             '0.05*mm,0.05*mm,198*mm' '0.05*mm,0.18*mm,198*mm' '0.05*mm,0.31*mm,198*mm' '0.05*mm,0.44*mm,198*mm' '0.05*mm,0.57*mm,198*mm' '0.05*mm,0.7*mm,198*mm' '0.05*mm,0.83*mm,198*mm' '0.05*mm,0.96*mm,198*mm' '0.05*mm,1.09*mm,198*mm' '0.05*mm,1.22*mm,198*mm' '0.05*mm,1.39*mm,198*mm' '0.82*mm,0.05*mm,198*mm' '0.82*mm,0.18*mm,198*mm' '0.82*mm,0.31*mm,198*mm' '0.82*mm,0.44*mm,198*mm' '0.82*mm,0.57*mm,198*mm' '0.82*mm,0.7*mm,198*mm' '0.82*mm,0.83*mm,198*mm' '0.82*mm,0.96*mm,198*mm' '0.82*mm,1.09*mm,198*mm' '0.82*mm,1.22*mm,198*mm' '0.82*mm,1.39*mm,198*mm' '1.58*mm,0.05*mm,198*mm' '1.58*mm,0.18*mm,198*mm' '1.58*mm,0.31*mm,198*mm' '1.58*mm,0.44*mm,198*mm' '1.58*mm,0.57*mm,198*mm' '1.58*mm,0.7*mm,198*mm' '1.58*mm,0.83*mm,198*mm' '1.58*mm,0.96*mm,198*mm' '1.58*mm,1.09*mm,198*mm' '1.58*mm,1.22*mm,198*mm' '1.58*mm,1.39*mm,198*mm' '2.34*mm,0.05*mm,198*mm' '2.34*mm,0.18*mm,198*mm' '2.34*mm,0.31*mm,198*mm' '2.34*mm,0.44*mm,198*mm' '2.34*mm,0.57*mm,198*mm' '2.34*mm,0.7*mm,198*mm' '2.34*mm,0.83*mm,198*mm' '2.34*mm,0.96*mm,198*mm' '2.34*mm,1.09*mm,198*mm' '2.34*mm,1.22*mm,198*mm' '2.34*mm,1.39*mm,198*mm' '2.0*mm,0.05*mm,198*mm' '2.0*mm,0.18*mm,198*mm' '2.0*mm,0.31*mm,198*mm' '2.0*mm,0.44*mm,198*mm' '2.0*mm,0.57*mm,198*mm' '2.0*mm,0.7*mm,198*mm' '2.0*mm,0.83*mm,198*mm' '2.0*mm,0.96*mm,198*mm' '2.0*mm,1.09*mm,198*mm' '2.0*mm,1.22*mm,198*mm' '2.0*mm,1.39*mm,198*mm' '1.28*mm,0.05*mm,198*mm' '1.28*mm,0.18*mm,198*mm' '1.28*mm,0.31*mm,198*mm' '1.28*mm,0.44*mm,198*mm' '1.28*mm,0.57*mm,198*mm' '1.28*mm,0.7*mm,198*mm' '1.28*mm,0.83*mm,198*mm' '1.28*mm,0.96*mm,198*mm' '1.28*mm,1.09*mm,198*mm' '1.28*mm,1.22*mm,198*mm' '1.28*mm,1.39*mm,198*mm' '2.5*mm,0.05*mm,198*mm' '2.5*mm,0.18*mm,198*mm' '2.5*mm,0.31*mm,198*mm' '2.5*mm,0.44*mm,198*mm' '2.5*mm,0.57*mm,198*mm' '2.5*mm,0.7*mm,198*mm' '2.5*mm,0.83*mm,198*mm' '2.5*mm,0.96*mm,198*mm' '2.5*mm,1.09*mm,198*mm' '2.5*mm,1.22*mm,198*mm' '2.5*mm,1.35*mm,198*mm' '1.73*mm,0.05*mm,198*mm' '1.73*mm,0.18*mm,198*mm' '1.73*mm,0.31*mm,198*mm' '1.73*mm,0.44*mm,198*mm' '1.73*mm,0.57*mm,198*mm' '1.73*mm,0.7*mm,198*mm' '1.73*mm,0.83*mm,198*mm' '1.73*mm,0.96*mm,198*mm' '1.73*mm,1.09*mm,198*mm' '1.73*mm,1.22*mm,198*mm' '1.73*mm,1.39*mm,198*mm' '0.97*mm,0.05*mm,198*mm' '0.97*mm,0.18*mm,198*mm' '0.97*mm,0.31*mm,198*mm' '0.97*mm,0.44*mm,198*mm' '0.97*mm,0.57*mm,198*mm' '0.97*mm,0.7*mm,198*mm' '0.97*mm,0.83*mm,198*mm' '0.97*mm,0.96*mm,198*mm' '0.97*mm,1.09*mm,198*mm' '0.97*mm,1.22*mm,198*mm' '0.97*mm,1.39*mm,198*mm' '0.21*mm,0.05*mm,198*mm' '0.21*mm,0.18*mm,198*mm' '0.21*mm,0.31*mm,198*mm' '0.21*mm,0.44*mm,198*mm' '0.21*mm,0.57*mm,198*mm' '0.21*mm,0.7*mm,198*mm' '0.21*mm,0.83*mm,198*mm' '0.21*mm,0.96*mm,198*mm' '0.21*mm,1.09*mm,198*mm' '0.21*mm,1.22*mm,198*mm' '0.21*mm,1.39*mm,198*mm' '0.55*mm,0.05*mm,198*mm' '0.55*mm,0.18*mm,198*mm' '0.55*mm,0.31*mm,198*mm' '0.55*mm,0.44*mm,198*mm' '0.55*mm,0.57*mm,198*mm' '0.55*mm,0.7*mm,198*mm' '0.55*mm,0.83*mm,198*mm' '0.55*mm,0.96*mm,198*mm' '0.55*mm,1.09*mm,198*mm' '0.55*mm,1.22*mm,198*mm' '0.55*mm,1.39*mm,198*mm' '1.28*mm,0.05*mm,198*mm' '1.28*mm,0.18*mm,198*mm' '1.28*mm,0.31*mm,198*mm' '1.28*mm,0.44*mm,198*mm' '1.28*mm,0.57*mm,198*mm' '1.28*mm,0.7*mm,198*mm' '1.28*mm,0.83*mm,198*mm' '1.28*mm,0.96*mm,198*mm' '1.28*mm,1.09*mm,198*mm' '1.28*mm,1.22*mm,198*mm' '1.28*mm,1.39*mm,198*mm'
    
#      #'0.51*mm,0.05*mm,198*mm' '0.97*mm,0.05*mm,198*mm' '1.43*mm,0.05*mm,198*mm' '1.89*mm,0.05*mm,198*mm' '2.35*mm,0.05*mm,198*mm'
#     #'0.1*mm,0.1*mm,198*mm' '0.62*mm,0.1*mm,198*mm' '1.04*mm,0.1*mm,198*mm' '1.46*mm,0.1*mm,198*mm' '1.88*mm,0.1*mm,198*mm' '2.4*mm,0.1*mm,198*mm'
#     #'0.3*mm,0.3*mm,198*mm' '0.3*mm,0.5*mm,198*mm' '0.3*mm,0.7*mm,198*mm' '0.3*mm,0.9*mm,198*mm' '0.3*mm,1.2*mm,198*mm' '0.3*mm,1.4*mm,198*mm' '0.5*mm,0.3*mm,198*mm' '0.5*mm,0.5*mm,198*mm' '0.5*mm,0.7*mm,198*mm' '0.5*mm,0.9*mm,198*mm' '0.5*mm,1.2*mm,198*mm' '0.5*mm,1.4*mm,198*mm' '0.7*mm,0.3*mm,198*mm' '0.7*mm,0.5*mm,198*mm' '0.7*mm,0.7*mm,198*mm' '0.7*mm,0.9*mm,198*mm' '0.7*mm,1.2*mm,198*mm' '0.7*mm,1.4*mm,198*mm'
#     #'0.3*mm,0.48*mm,198*mm' '0.3*mm,0.75*mm,198*mm' '0.3*mm,1.02*mm,198*mm' '0.3*mm,1.29*mm,198*mm' '0.3*mm,1.56*mm,198*mm'
#     #'1.25*mm,0.8*mm,198*mm'
#      #'1.25*mm,0.835*mm,69*mm' '0.3*mm,0.1*mm,69*mm' '0.3*mm,0.31*mm,69*mm' '0.3*mm,0.64*mm,69*mm' '0.3*mm,1.25*mm,29*mm'

# #rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/paths

want paths/drift3d \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
     --paths paths/drift3d '0*us,600*us,0.1*us'
    #--paths paths/drift3d '0*us,4250*us,0.1*us'



pochoir extendwf -p store/potential/weight2d -P store/potential/weight3dfull -n 10 -o store/potential/weight3dextend


want current/induced_current_avg_ind \
     pochoir induce --weighting potential/weight3dextend \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind


date

