#!/bin/bash

if [[ $# -lt 2 ]]; then
    echo "please provide the run folder, and 2. the list of faults"
    echo "./extract_all.sh $gmsim/Runfolder/Cybershake/v18p7/Runs $gmsim/Runfolder/Cybershake/v18p7/list_all_r"
    exit 1
fi


run_folder=$1
list_all_r=$2

lf_tar_name='LF.tar'
lf_temp_name='LF'
for fault in `cat $list_all_r | awk '{print $1}'`;
do
 #   echo $fault
#
    for realization in $run_folder/$fault/*/;
    do
        tar -xvf $realization/$lf_tar_name -C $realization/
    done
done
