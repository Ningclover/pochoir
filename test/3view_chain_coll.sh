#!/bin/bash

source test-full-3d-velo.sh
source test-full-3d-paths_shift_30deg_coll.sh #collection
#source test-full-3d-paths_shift_both_30deg.sh #induction

export POCHOIR_STORE="${1:-store}"

pochoir extendwf -p store/potential/weight2d -P store/potential/weight3dfull -n 10 -o store/potential/weight3dextend

pochoir induce -w store/potential/weight3dextend -p store/paths/drift3d -a 11 -n 21 -O store/current/induced_current_avg_coll_ext

#pochoir induce-30deg -w store/potential/weight3dextend -p store/paths/drift3d -a 11 -n 21 -O store/current/induced_current_avg_ind1_ext

#pochoir convertfr -u store/all_currents/induced_current_avg_ind1_ext -v store/all_currents/induced_current_avg_ind2_ext -w store/all_currents/induced_current_avg_coll_ext -O store/all_currents/FR_HigherV_89K.json.bz2 example_converter_config_30deg.json
