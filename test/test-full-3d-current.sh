#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


want current/induced_current_avg_Ind1_ \
     pochoir induce-30deg --weighting potential/weight3dextend \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind1_p2_ext \
     --average 11.0 \
     --nstrips 21.0


