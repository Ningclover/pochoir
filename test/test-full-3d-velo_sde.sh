#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/velocity

want velocity/drift3d_ \
     pochoir velo --temperature '87.0*K' \
     --potential potential/drift3d \
     --velocity velocity/drift3d \
     --diff-longitudinal velocity/longdif \
     --diff-transverse velocity/trandif

#87k is standard for 500 drift
