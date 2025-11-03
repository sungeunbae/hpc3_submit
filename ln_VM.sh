#!/bin/bash

if [[ $# -lt 2 ]]; then
    echo "Usage $0 src_root dest_root"
    echo "$0 $gmsim/Runfolder/Cybershake/v18p7 $gmsim/Runfolder/Cybershake/v18p7_2"
    exit 1
fi

src_folder=$1
dest_folder=$2

src_vm_data=$src_folder/Data/VMs
dest_vm_data=$dest_folder/Data/VMs


echo "============ Making VM symbolic links =========="
if [ -d $dest_vm_data ]; then
    echo "$dest_vm_data already exists"
    if [ -L $dest_vm_data ]; then
	    echo "It is already a link - nothing to do."
	    exit
    else
	    dest_vm_data_backup=${dest_vm_data}_backup
	    echo "Existing copy found - renaming it to $dest_vm_data_backup. Can be deleted later"
	    mv $dest_vm_data $dest_vm_data_backup
    fi
fi
src_vm_data_abs=`realpath $src_vm_data`
ln -s $src_vm_data_abs $dest_vm_data
echo "Link created $dest_vm_data -> $src_vm_data_abs"


