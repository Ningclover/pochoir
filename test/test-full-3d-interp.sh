#!/bin/bash

set -e
export POCHOIR_STORE="${1:-store}"
#tdir="$(dirname $(realpath $BASH_SOURCE))"



source helpers.sh

#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


# special step to form iva/bva from 2D solution
want initial/weight3dfull_my \
     pochoir bc-interp --xcoord '17.5*mm' \
     --initial initial/weight3dfull_t --boundary boundary/weight3dfull_t \
     --initial3d initial/weight3d --boundary3d boundary/weight3d \
     --potential2d potential/weight2d
