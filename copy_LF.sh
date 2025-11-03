#!/bin/bash

#!/bin/bash

if [[ $# -lt 3 ]]; then
    echo "Usage $0 src_root dest_root fault_list"
    echo "$0 $gmsim/Runfolder/Cybershake/v18p7 $gmsim/Runfolder/Cybershake/v18p7/list_all_r $gmsim/Runfolder/Cybershake/v18p7_2"
    exit 1
fi

src_folder=$1
dest_folder=$2
list_all_r=$3

src_runs=$src_folder/Runs
dest_runs=$dest_folder/Runs

lf_tar_name='LF.tar'
lf_temp_name='LF_temp'
#lf_temp_name='LF'

echo "========= Copying LF.tar and extracting ======="
for fault in `cat $list_all_r | awk '{print $1}'`;
do
    echo $fault
#
    for realization in `find $src_runs/$fault/ -maxdepth 1 -mindepth 1 -type d`;
    do
        realization_basename=`basename $realization`
	tar xvf $realization/$lf_tar_name -C $realization
	mkdir -p $dest_runs/$fault/$realization_basename/LF
        cp -r $realization/$lf_temp_name/* $dest_runs/$fault/$realization_basename/LF/
    done
