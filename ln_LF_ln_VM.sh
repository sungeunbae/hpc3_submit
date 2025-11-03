#!/bin/bash

if [[ $# -lt 3 ]]; then
    echo "Usage $0 src_root dest_root fault_list"
    echo "$0 $gmsim/Runfolder/Cybershake/v18p7 $gmsim/Runfolder/Cybershake/v18p7/list_all_r $gmsim/Runfolder/Cybershake/v18p7_2"
    exit 1
fi

src_folder=`realpath $1`
dest_folder=`realpath $2`
list_all_r=`realpath $3`

src_vm_data=$src_folder/Data/VMs
dest_vm_data=$dest_folder/Data/VMs

src_runs=$src_folder/Runs
dest_runs=$dest_folder/Runs

lf_tar_name='LF.tar'
lf_temp_name='LF_temp'
lf_good_name='LF'


echo "============ Making VM symbolic links =========="
if [ -d $dest_vm_data ]; then
    echo "$dest_vm_data already exists"
    if [ -L $dest_vm_data ]; then
	    echo "It is already a link - nothing to do."
#	    exit
    else
	    dest_vm_data_backup=${dest_vm_data}_backup
	    echo "Existing copy found - renaming it to $dest_vm_data_backup. Can be deleted later"
	    mv $dest_vm_data $dest_vm_data_backup
    fi
fi
#echo mkdir -p $dest_folder/Data
mkdir -p $dest_folder/Data

#echo ln -s $src_vm_data $dest_vm_data
if [ -L $dest_vm_data ]; then
    echo "Keeping the existing VM data symbolic link"
else
    ln -s $src_vm_data $dest_vm_data
    echo "Link created $dest_vm_data -> $src_vm_data_abs"
fi


echo "========= Linking existing LF output ======="
for fault in `cat $list_all_r | awk '{print $1}'`;
do
    fault=$(echo "$fault" |sed 's/\r$//')
    echo
    echo $fault

#
    for realization in `find $src_runs/$fault/ -maxdepth 1 -mindepth 1 -type d`;
    do
        realization_basename=`basename $realization`
        
	if [ -d "$realization/$lf_good_name" ]; then
            echo "Checking  $realization/$lf_good_name"
        else
            echo "ERROR: $realzation/$lf_good_name not found"
            continue
	fi

        runs_dir=$dest_runs/$fault/$realization_basename

        mkdir -p $runs_dir

	ln_ok=1
        if [ -e "$runs_dir/LF" ]; then
            if [ -L "$runs_dir/LF" ]; then
                echo "Already existing: $runs_dir/LF is a symbolic link...safe to delete and recreate"
                rm $runs_dir/LF
#                echo "Do you want to delete it to proceed?? (y/n)"
#                read input
#                if [ "$input" == "y" ]; then
#                   echo "Deleting"
#                   rm $runs_dir/LF
#                else
#                   ln_ok=0
#                   echo "Keeping $runs_dir/LF"
#                fi
            elif [ -d "$runs_dir/LF" ]; then
                echo "Already existing: $runs_dir/LF is a directory"
                tree $runs_dir/LF |head -20
                echo "......"
                if [ -z "$( ls -A $runs_dir/LF )" ]; then
                   echo "Empty, ok to delete"
                else
                   echo "Not Empty. Not safe to delete! Examine please"
                fi
                echo "Do you want to delete it to proceed?? (y/n)"
                read input
                if [ "$input" == "y" ]; then
                   echo "Deleting"
                   rm -rf $runs_dir/LF
                else
                   echo "EXITING for investigation"
                   exit 2
                fi
             else
                echo "$runs_dir/LF is in wrong type (neither directory or symlink)"
                exit 2
             fi
        fi

        if [ "$ln_ok" -eq "1" ]; then
            echo "symlink created : $realization/$lf_good_name-> $runs_dir/LF"
	    ln -s `realpath $realization/$lf_good_name` $runs_dir/LF
        else
            echo "symlink skipped"
        fi
    done
    
done
