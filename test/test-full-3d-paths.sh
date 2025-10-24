#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


want velocity/drift3d \
     pochoir velo --temperature '89*K' \
     --potential potential/drift3d \
     --velocity velocity/drift3d


want starts/drift3d \
    pochoir starts --starts starts/drift3d \
    '0.05*mm,0.05*mm,198*mm' '0.05*mm,0.2*mm,198*mm' '0.05*mm,0.35*mm,198*mm' '0.05*mm,0.5*mm,198*mm' '0.05*mm,0.65*mm,198*mm' '0.05*mm,0.8*mm,198*mm' '0.05*mm,0.95*mm,198*mm' '0.05*mm,1.1*mm,198*mm' '0.05*mm,1.25*mm,198*mm' '0.05*mm,1.4*mm,198*mm' '0.05*mm,1.55*mm,198*mm' '0.51*mm,0.05*mm,198*mm' '0.51*mm,0.2*mm,198*mm' '0.51*mm,0.35*mm,198*mm' '0.51*mm,0.5*mm,198*mm' '0.51*mm,0.65*mm,198*mm' '0.51*mm,0.8*mm,198*mm' '0.51*mm,0.95*mm,198*mm' '0.51*mm,1.1*mm,198*mm' '0.51*mm,1.25*mm,198*mm' '0.51*mm,1.4*mm,198*mm' '0.51*mm,1.55*mm,198*mm' '0.97*mm,0.05*mm,198*mm' '0.97*mm,0.2*mm,198*mm' '0.97*mm,0.35*mm,198*mm' '0.97*mm,0.5*mm,198*mm' '0.97*mm,0.65*mm,198*mm' '0.97*mm,0.8*mm,198*mm' '0.97*mm,0.95*mm,198*mm' '0.97*mm,1.1*mm,198*mm' '0.97*mm,1.25*mm,198*mm' '0.97*mm,1.4*mm,198*mm' '0.97*mm,1.55*mm,198*mm' '1.43*mm,0.05*mm,198*mm' '1.43*mm,0.2*mm,198*mm' '1.43*mm,0.35*mm,198*mm' '1.43*mm,0.5*mm,198*mm' '1.43*mm,0.65*mm,198*mm' '1.43*mm,0.8*mm,198*mm' '1.43*mm,0.95*mm,198*mm' '1.43*mm,1.1*mm,198*mm' '1.43*mm,1.25*mm,198*mm' '1.43*mm,1.4*mm,198*mm' '1.43*mm,1.55*mm,198*mm' '1.89*mm,0.05*mm,198*mm' '1.89*mm,0.2*mm,198*mm' '1.89*mm,0.35*mm,198*mm' '1.89*mm,0.5*mm,198*mm' '1.89*mm,0.65*mm,198*mm' '1.89*mm,0.8*mm,198*mm' '1.89*mm,0.95*mm,198*mm' '1.89*mm,1.1*mm,198*mm' '1.89*mm,1.25*mm,198*mm' '1.89*mm,1.4*mm,198*mm' '1.89*mm,1.55*mm,198*mm' '2.35*mm,0.05*mm,198*mm' '2.35*mm,0.2*mm,198*mm' '2.35*mm,0.35*mm,198*mm' '2.35*mm,0.5*mm,198*mm' '2.35*mm,0.65*mm,198*mm' '2.35*mm,0.8*mm,198*mm' '2.35*mm,0.95*mm,198*mm' '2.35*mm,1.1*mm,198*mm' '2.35*mm,1.25*mm,198*mm' '2.35*mm,1.4*mm,198*mm' '2.35*mm,1.55*mm,198*mm'
    
     #'0.51*mm,0.05*mm,198*mm' '0.97*mm,0.05*mm,198*mm' '1.43*mm,0.05*mm,198*mm' '1.89*mm,0.05*mm,198*mm' '2.35*mm,0.05*mm,198*mm'
    #'0.1*mm,0.1*mm,198*mm' '0.62*mm,0.1*mm,198*mm' '1.04*mm,0.1*mm,198*mm' '1.46*mm,0.1*mm,198*mm' '1.88*mm,0.1*mm,198*mm' '2.4*mm,0.1*mm,198*mm'
    #'0.3*mm,0.3*mm,198*mm' '0.3*mm,0.5*mm,198*mm' '0.3*mm,0.7*mm,198*mm' '0.3*mm,0.9*mm,198*mm' '0.3*mm,1.2*mm,198*mm' '0.3*mm,1.4*mm,198*mm' '0.5*mm,0.3*mm,198*mm' '0.5*mm,0.5*mm,198*mm' '0.5*mm,0.7*mm,198*mm' '0.5*mm,0.9*mm,198*mm' '0.5*mm,1.2*mm,198*mm' '0.5*mm,1.4*mm,198*mm' '0.7*mm,0.3*mm,198*mm' '0.7*mm,0.5*mm,198*mm' '0.7*mm,0.7*mm,198*mm' '0.7*mm,0.9*mm,198*mm' '0.7*mm,1.2*mm,198*mm' '0.7*mm,1.4*mm,198*mm'
    #'0.3*mm,0.48*mm,198*mm' '0.3*mm,0.75*mm,198*mm' '0.3*mm,1.02*mm,198*mm' '0.3*mm,1.29*mm,198*mm' '0.3*mm,1.56*mm,198*mm'
    #'1.25*mm,0.8*mm,198*mm'
     #'1.25*mm,0.835*mm,69*mm' '0.3*mm,0.1*mm,69*mm' '0.3*mm,0.37*mm,69*mm' '0.3*mm,0.64*mm,69*mm' '0.3*mm,1.25*mm,29*mm'

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/paths

want paths/drift3d_tight \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
     --paths paths/drift3d_tight '0*us,600*us,0.02*us'
    #--paths paths/drift3d '0*us,4250*us,0.1*us'

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/current

#want current/induced_current_avg_ind \
     pochoir induce --weighting potential/weight3dfull_ind \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind


