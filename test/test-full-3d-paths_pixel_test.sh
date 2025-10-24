 #!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


want starts/drift3d \
    pochoir starts --starts starts/drift3d \
    '1.9*mm,3.7*mm,148*mm',
#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/paths

want paths/drift3d_tight_ \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
     --paths paths/drift3d_tight '0*us,320*us,0.05*us'
    #--paths paths/drift3d '0*us,4250*us,0.1*us'

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/current

#want current/induced_current_avg_ind \
     pochoir induce --weighting potential/weight3dfull_ind \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind


