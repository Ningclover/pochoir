#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/velocity

want velocity/drift3d \
     pochoir velo --temperature '89*K' \
     --potential potential/drift3d \
     --velocity velocity/drift3d

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/starts

want starts/drift3d \
    pochoir starts --starts starts/drift3d \
    '0.3*mm,0.3*mm,198*mm' '0.3*mm,0.5*mm,198*mm' '0.3*mm,0.7*mm,198*mm' '0.3*mm,0.9*mm,198*mm' '0.3*mm,1.2*mm,198*mm' '0.3*mm,1.4*mm,198*mm' '0.5*mm,0.3*mm,198*mm' '0.5*mm,0.5*mm,198*mm' '0.5*mm,0.7*mm,198*mm' '0.5*mm,0.9*mm,198*mm' '0.5*mm,1.2*mm,198*mm' '0.5*mm,1.4*mm,198*mm' '0.7*mm,0.3*mm,198*mm' '0.7*mm,0.5*mm,198*mm' '0.7*mm,0.7*mm,198*mm' '0.7*mm,0.9*mm,198*mm' '0.7*mm,1.2*mm,198*mm' '0.7*mm,1.4*mm,198*mm'
    #'0.3*mm,0.48*mm,198*mm' '0.3*mm,0.75*mm,198*mm' '0.3*mm,1.02*mm,198*mm' '0.3*mm,1.29*mm,198*mm' '0.3*mm,1.56*mm,198*mm'
    #'1.25*mm,0.8*mm,198*mm'
     #'1.25*mm,0.835*mm,69*mm' '0.3*mm,0.1*mm,69*mm' '0.3*mm,0.37*mm,69*mm' '0.3*mm,0.64*mm,69*mm' '0.3*mm,1.25*mm,29*mm'

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/paths

want paths/drift3d \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
     --paths paths/drift3d '0*us,4250*us,0.1*us'
    #--paths paths/drift3d '0*us,4250*us,0.1*us'


