#!/bin/bash

set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


want starts/drift3d \
    pochoir starts --starts starts/drift3d \
    '0.1*mm,0.1*mm,148*mm', '0.5*mm,0.1*mm,148*mm', '1.0*mm,0.1*mm,148*mm', '1.5*mm,0.1*mm,148*mm', ,'1.9*mm,0.1*mm,148*mm', '2.1*mm,0.1*mm,148*mm', '2.3*mm,0.1*mm,148*mm', '2.5*mm,0.1*mm,148*mm', '3.0*mm,0.1*mm,148*mm', '3.5*mm,0.1*mm,148*mm', '4.0*mm,0.1*mm,148*mm', '4.3*mm,0.1*mm,148*mm', '0.1*mm,0.5*mm,148*mm', '0.5*mm,0.5*mm,148*mm', '1.0*mm,0.5*mm,148*mm', '1.5*mm,0.5*mm,148*mm', ,'1.9*mm,0.5*mm,148*mm', '2.1*mm,0.5*mm,148*mm', '2.3*mm,0.5*mm,148*mm', '2.5*mm,0.5*mm,148*mm', '3.0*mm,0.5*mm,148*mm', '3.5*mm,0.5*mm,148*mm', '4.0*mm,0.5*mm,148*mm', '4.3*mm,0.5*mm,148*mm', '0.1*mm,1.0*mm,148*mm', '0.5*mm,1.0*mm,148*mm', '1.0*mm,1.0*mm,148*mm', '1.5*mm,1.0*mm,148*mm', ,'1.9*mm,1.0*mm,148*mm', '2.1*mm,1.0*mm,148*mm', '2.3*mm,1.0*mm,148*mm', '2.5*mm,1.0*mm,148*mm', '3.0*mm,1.0*mm,148*mm', '3.5*mm,1.0*mm,148*mm', '4.0*mm,1.0*mm,148*mm', '4.3*mm,1.0*mm,148*mm', '0.1*mm,1.9*mm,148*mm', '0.5*mm,1.9*mm,148*mm', '1.0*mm,1.9*mm,148*mm', '1.5*mm,1.9*mm,148*mm', ,'1.9*mm,1.9*mm,148*mm', '2.1*mm,1.9*mm,148*mm', '2.3*mm,1.9*mm,148*mm', '2.5*mm,1.9*mm,148*mm', '3.0*mm,1.9*mm,148*mm', '3.5*mm,1.9*mm,148*mm', '4.0*mm,1.9*mm,148*mm', '4.3*mm,1.9*mm,148*mm', '0.1*mm,2.1*mm,148*mm', '0.5*mm,2.1*mm,148*mm', '1.0*mm,2.1*mm,148*mm', '1.5*mm,2.1*mm,148*mm', '1.9*mm,2.1*mm,148*mm', '2.1*mm,2.1*mm,148*mm', '2.3*mm,2.1*mm,148*mm', '2.5*mm,2.1*mm,148*mm', '3.0*mm,2.1*mm,148*mm', '3.5*mm,2.1*mm,148*mm', '4.0*mm,2.1*mm,148*mm', '4.3*mm,2.1*mm,148*mm', '0.1*mm,2.5*mm,148*mm', '0.5*mm,2.5*mm,148*mm', '1.0*mm,2.5*mm,148*mm', '1.5*mm,2.5*mm,148*mm', '1.9*mm,2.5*mm,148*mm', '2.1*mm,2.5*mm,148*mm', '2.3*mm,2.5*mm,148*mm', '2.5*mm,2.5*mm,148*mm', '3.0*mm,2.5*mm,148*mm', '3.5*mm,2.5*mm,148*mm', '4.0*mm,2.5*mm,148*mm', '4.3*mm,2.5*mm,148*mm', '0.1*mm,3.0*mm,148*mm', '0.5*mm,3.0*mm,148*mm', '1.0*mm,3.0*mm,148*mm', '1.5*mm,3.0*mm,148*mm', '1.9*mm,3.0*mm,148*mm', '2.1*mm,3.0*mm,148*mm', '2.3*mm,3.0*mm,148*mm', '2.5*mm,3.0*mm,148*mm', '3.0*mm,3.0*mm,148*mm', '3.5*mm,3.0*mm,148*mm', '4.0*mm,3.0*mm,148*mm', '4.3*mm,3.0*mm,148*mm', '0.1*mm,4.3*mm,148*mm', '0.5*mm,4.3*mm,148*mm', '1.0*mm,4.3*mm,148*mm', '1.5*mm,4.3*mm,148*mm', '1.9*mm,4.3*mm,148*mm', '2.1*mm,4.3*mm,148*mm', '2.3*mm,4.3*mm,148*mm', '2.5*mm,4.3*mm,148*mm', '3.0*mm,4.3*mm,148*mm', '3.5*mm,4.3*mm,148*mm', '4.0*mm,4.3*mm,148*mm', '4.3*mm,4.3*mm,148*mm'
#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/paths

want paths/drift3d_tight \
     pochoir drift --starts starts/drift3d \
     --velocity velocity/drift3d \
     --paths paths/drift3d_tight '0*us,320*us,0.05*us'
    #--paths paths/drift3d '0*us,4250*us,0.1*us'

#rm -r /Users/sergey/Desktop/ICARUS/LArStand/pochoir/test/store/current

#want current/induced_current_avg_ind \
     pochoir induce --weighting potential/weight3dfull_ind \
     --paths paths/drift3d \
     --output current/induced_current_avg_ind


