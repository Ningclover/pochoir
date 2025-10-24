#!/bin/bash

#set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/velocity
# '19.125*mm' collection

want initial/weight3dfull \
     pochoir bc-interp --xcoord '26.775*mm' \
     --initial initial/weight3dfull --boundary boundary/weight3dfull \
     --initial3d initial/weight3d --boundary3d boundary/weight3d \
     --potential2d potential/weight2d

