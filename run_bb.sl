#!/bin/bash
# script version: slurm
# BB calculation
#

# Please modify this file as needed, this is just a sample
#SBATCH --account=nesi00213
#SBATCH --job-name=bb.$JOBNAME
#SBATCH --partition=genoa
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=42
#SBATCH --time=00:03:00
##SBATCH --mem=84G # maxmem 

set -eou pipefail

## END HEADER

## Get the current working directory
REL_DIR="$PWD"
FAULT_DIR=$(dirname "$REL_DIR")

BASE_DIR=$(dirname "$(dirname "$FAULT_DIR")")
echo "REL_DIR=$REL_DIR"
echo "BASE_DIR=$BASE_DIR"

# Retrieve memory and wall clock time dynamically
MEMORY=${SLURM_MEM_PER_NODE:-"Unknown"}
#WCT=${SLURM_TIMELIMIT:-"Unknown"}
WCT=$(squeue -j "$SLURM_JOB_ID" -h -o "%l")

echo "Fix old NeSI path"

# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true


# Check if e3d.par exists, generate if missing
if [[ ! -f "$REL_DIR/LF/e3d.par" ]]; then
    echo "e3d.par not found, generating..."
    python $gmsim/workflow/workflow/calculation/create_e3d.py "$REL_DIR"
fi

#updating the stats in managementDB
# Updating the stats in managementDB
if [[ ! -d "$BASE_DIR/mgmt_db_queue" ]]; then
    mkdir "$BASE_DIR/mgmt_db_queue"
fi


SUCCESS_CODE=0

# Print configuration to stdout
echo "#############################################"
echo "Job Configuration:"
echo "Job Name: $JOBNAME"
echo "Nodes: $SLURM_NNODES"
echo "Tasks per Node: $SLURM_NTASKS_PER_NODE"
echo "Memory per Node (sbatch --mem) : $(awk "BEGIN {printf \"%.2f\", $MEMORY / 1024}") GB"
echo "Wall Clock Time: $WCT"
echo "#############################################"
runtime_fmt="%Y-%m-%d_%H:%M:%S"
start_time=`date +$runtime_fmt`
echo $start_time
start_epoch=$(date +%s)

#python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $BASE_DIR/mgmt_db_queue $JOBNAME BB running $SLURM_JOB_ID --start_time "$start_time" --nodes $SLURM_NNODES --cores $SLURM_NTASKS --wct "$wct"

echo "Computing BB"
mkdir -p $REL_DIR/BB/Acc
 srun python $gmsim/workflow/workflow/calculation/bb_sim.py $REL_DIR/LF/OutBin $BASE_DIR/Data/VMs/$JOBNAME $REL_DIR/HF/Acc/HF.bin /nesi/project/nesi00213/StationInfo/geoNet_stats+2023-06-28.vs30 $REL_DIR/BB/Acc/BB.bin --flo 1.0 --fmin 0.2 --fmidbot 0.5 --dt 0.005

end_time=`date +$runtime_fmt`
echo $end_time
end_epoch=$(date +%s)

# Calculate the difference
runtime_seconds=$((end_epoch - start_epoch))
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"


#test before update
res=`$gmsim/workflow/workflow/calculation/verification/test_bb.sh $REL_DIR `
if [[ $? == 0 ]]; then
    #passed
#    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $BASE_DIR/mgmt_db_queue $JOBNAME BB completed $SLURM_JOB_ID --end_time "$end_time"

    if [[ ! -d $REL_DIR/ch_log ]]; then
        mkdir $REL_DIR/ch_log
    fi
    fd_name=`python -c "from qcore import utils; pb = utils.load_sim_params('$REL_DIR/sim_params.yaml'); print(pb['FD_STATLIST'])"`
    fd_count=`cat $fd_name | wc -l`
    
    # save meta data
    python $gmsim/workflow/workflow/automation/metadata/log_metadata.py $REL_DIR BB cores=$SLURM_NTASKS fd_count=$fd_count start_time=$start_time end_time=$end_time status="COMPLETED"
else
    #reformat $res to remove '\n'
    res=`echo $res | tr -d '\n'`
#    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $BASE_DIR/mgmt_db_queue $JOBNAME BB failed $SLURM_JOB_ID --error "$res" --end_time "$end_time"
    backup_directory="$nobackup/tmp/$USER/""$SLURM_JOB_ID""_${JOBNAME}_BB"
    echo "Completion test failed, moving all files to $backup_directory"
    echo "Failure reason: $res"
    mkdir -p $backup_directory
    mv $REL_DIR/BB/* $backup_directory
fi
