 #!/bin/bash

#set -e

#tdir="$(dirname $(realpath $BASH_SOURCE))"

export POCHOIR_STORE="${1:-store}"

source helpers.sh


want starts/drift3d_ \
    pochoir starts --starts starts/drift3d \
    -m yes \
    '0.1*mm,0.1*mm,148*mm','0.1*mm,0.57*mm,148*mm','0.1*mm,1.04*mm,148*mm','0.1*mm,1.51*mm,148*mm','0.1*mm,1.98*mm,148*mm','0.1*mm,2.45*mm,148*mm','0.1*mm,2.92*mm,148*mm','0.1*mm,3.39*mm,148*mm','0.1*mm,3.86*mm,148*mm','0.1*mm,4.3*mm,148*mm','0.57*mm,0.1*mm,148*mm','0.57*mm,0.57*mm,148*mm','0.57*mm,1.04*mm,148*mm','0.57*mm,1.51*mm,148*mm','0.57*mm,1.98*mm,148*mm','0.57*mm,2.45*mm,148*mm','0.57*mm,2.92*mm,148*mm','0.57*mm,3.39*mm,148*mm','0.57*mm,3.86*mm,148*mm','0.57*mm,4.3*mm,148*mm','1.04*mm,0.1*mm,148*mm','1.04*mm,0.57*mm,148*mm','1.04*mm,1.04*mm,148*mm','1.04*mm,1.51*mm,148*mm','1.04*mm,1.98*mm,148*mm','1.04*mm,2.45*mm,148*mm','1.04*mm,2.92*mm,148*mm','1.04*mm,3.39*mm,148*mm','1.04*mm,3.86*mm,148*mm','1.04*mm,4.3*mm,148*mm','1.51*mm,0.1*mm,148*mm','1.51*mm,0.57*mm,148*mm','1.51*mm,1.04*mm,148*mm','1.51*mm,1.51*mm,148*mm','1.51*mm,1.98*mm,148*mm','1.51*mm,2.45*mm,148*mm','1.51*mm,2.92*mm,148*mm','1.51*mm,3.39*mm,148*mm','1.51*mm,3.86*mm,148*mm','1.51*mm,4.3*mm,148*mm','1.98*mm,0.1*mm,148*mm','1.98*mm,0.57*mm,148*mm','1.98*mm,1.04*mm,148*mm','1.98*mm,1.51*mm,148*mm','1.98*mm,1.98*mm,148*mm','1.98*mm,2.45*mm,148*mm','1.98*mm,2.92*mm,148*mm','1.98*mm,3.39*mm,148*mm','1.98*mm,3.86*mm,148*mm','1.98*mm,4.3*mm,148*mm','2.45*mm,0.1*mm,148*mm','2.45*mm,0.57*mm,148*mm','2.45*mm,1.04*mm,148*mm','2.45*mm,1.51*mm,148*mm','2.45*mm,1.98*mm,148*mm','2.45*mm,2.45*mm,148*mm','2.45*mm,2.92*mm,148*mm','2.45*mm,3.39*mm,148*mm','2.45*mm,3.86*mm,148*mm','2.45*mm,4.3*mm,148*mm','2.92*mm,0.1*mm,148*mm','2.92*mm,0.57*mm,148*mm','2.92*mm,1.04*mm,148*mm','2.92*mm,1.51*mm,148*mm','2.92*mm,1.98*mm,148*mm','2.92*mm,2.45*mm,148*mm','2.92*mm,2.92*mm,148*mm','2.92*mm,3.39*mm,148*mm','2.92*mm,3.86*mm,148*mm','2.92*mm,4.3*mm,148*mm','3.39*mm,0.1*mm,148*mm','3.39*mm,0.57*mm,148*mm','3.39*mm,1.04*mm,148*mm','3.39*mm,1.51*mm,148*mm','3.39*mm,1.98*mm,148*mm','3.39*mm,2.45*mm,148*mm','3.39*mm,2.92*mm,148*mm','3.39*mm,3.39*mm,148*mm','3.39*mm,3.86*mm,148*mm','3.39*mm,4.3*mm,148*mm','3.86*mm,0.1*mm,148*mm','3.86*mm,0.57*mm,148*mm','3.86*mm,1.04*mm,148*mm','3.86*mm,1.51*mm,148*mm','3.86*mm,1.98*mm,148*mm','3.86*mm,2.45*mm,148*mm','3.86*mm,2.92*mm,148*mm','3.86*mm,3.39*mm,148*mm','3.86*mm,3.86*mm,148*mm','3.86*mm,4.3*mm,148*mm','4.3*mm,0.1*mm,148*mm','4.3*mm,0.57*mm,148*mm','4.3*mm,1.04*mm,148*mm','4.3*mm,1.51*mm,148*mm','4.3*mm,1.98*mm,148*mm','4.3*mm,2.45*mm,148*mm','4.3*mm,2.92*mm,148*mm','4.3*mm,3.39*mm,148*mm','4.3*mm,3.86*mm,148*mm','4.3*mm,4.3*mm,148*mm'
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


