#!/bin/bash
# script version: slurm
# HF calculation
#

# Please modify this file as needed, this is just a sample
#SBATCH --account=nesi00213
#SBATCH --job-name=hf.$JOBNAME
#SBATCH --partition=genoa
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=168
#SBATCH --time=10:00:00
##SBATCH --mem=420G # maxmem

set -eou pipefail

## END HEADER
SCRIPTS_DIR=/nesi/nobackup/nesi00213/RunFolder/submit
## Get the current working directory
REL_DIR="$PWD"
FAULT_DIR=$(dirname "$REL_DIR")

BASE_DIR=$(dirname "$(dirname "$FAULT_DIR")")

echo "REL_DIR=$REL_DIR"
echo "BASE_DIR=$BASE_DIR"
REL_NAME=$(basename "$REL_DIR")
echo "REL_NAME=$REL_NAME"

# Retrieve memory and wall clock time dynamically
MEMORY=${SLURM_MEM_PER_NODE:-"Unknown"}
#WCT=${SLURM_TIMELIMIT:-"Unknown"}
WCT=$(squeue -j "$SLURM_JOB_ID" -h -o "%l")


echo "Changing to FAULT_DIR: $FAULT_DIR"

# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true



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

echo "Computing HF"
mkdir -p $REL_DIR/HF/Acc

cmd=`python $SCRIPTS_DIR/run_hf_command.py $REL_DIR`
echo $cmd
$cmd

end_time=`date +$runtime_fmt`
echo $end_time
end_epoch=$(date +%s)

# Calculate the difference
runtime_seconds=$((end_epoch - start_epoch))
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"

#test before update
res=`$gmsim/workflow/workflow/calculation/verification/test_hf.sh $REL_DIR `
success=$?
if [[ $success == $SUCCESS_CODE ]]; then
    #passed
    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $BASE_DIR/mgmt_db_queue ${REL_NAME} HF completed $SLURM_JOB_ID --end_time "$end_time"

    #save the parameters
    if [[ ! -d $REL_DIR/ch_log ]]; then
        mkdir $REL_DIR/ch_log
    fi
    fd_name=`python -c "from qcore import utils; p = utils.load_sim_params('$REL_DIR/sim_params.yaml'); print(p['FD_STATLIST'])"`
    fd_count=`cat $fd_name | wc -l`

    # Save meta data
    python $gmsim/workflow/workflow/automation/metadata/log_metadata.py $REL_DIR HF cores=$SLURM_NTASKS fd_count=$fd_count start_time=$start_time end_time=$end_time status="COMPLETED"
else
    #reformat $res to remove '\n'
    res=`echo $res | tr -d '\n'`
    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $BASE_DIR/mgmt_db_queue $REL_NAME HF failed $SLURM_JOB_ID --error "$res" --end_time "$end_time"
    backup_directory="$nobackup/tmp/$USER/""$SLURM_JOB_ID""_${REL_NAME}_HF"
    echo "Completion test failed, moving all files to $backup_directory"
    echo "Failure reason: $res"
    mkdir -p $backup_directory
    mv $REL_DIR/HF/* $backup_directory
fi
