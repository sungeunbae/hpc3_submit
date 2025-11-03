#!/bin/bash
#SBATCH --account=nesi00213
#SBATCH --job-name=im_array
#SBATCH --partition=genoa
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=42
#SBATCH --time=00:10:00
#SBATCH --mem=84G
#SBATCH --array=0-18%5  # Adjust based on the number of lines in im_targets.txt and concurrency
#SBATCH --output=logs/im_%A_%a.out
#SBATCH --error=logs/im_%A_%a.err

#set -eou pipefail

SCRIPTS_DIR=/nesi/nobackup/nesi00213/RunFolder/submit
BASE_DIR=$PWD

TARGET_LIST=${BASE_DIR}/im_targets.txt
REL_DIR=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$TARGET_LIST")

if [[ -z "$REL_DIR" ]]; then
    echo "⚠️ SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID is out of range for $TARGET_LIST. Exiting."
    exit 0
fi

REL_NAME=$(basename "$REL_DIR")
FAULT_DIR=$(dirname "$REL_DIR")
MGMT_DB_QUEUE="$BASE_DIR/mgmt_db_queue"

echo "REL_DIR=$REL_DIR"
echo "BASE_DIR=$BASE_DIR"
echo "REL_NAME=$REL_NAME"


WCT=$(squeue -j "$SLURM_JOB_ID" -h -o "%l")

function getFromYaml {
    echo $(python -c "from qcore.utils import load_sim_params; print(load_sim_params('$1')['$2'])")
}

runtime_fmt="%Y-%m-%d_%H:%M:%S"


start_time=$(date +"%Y-%m-%d_%H:%M:%S")
start_epoch=$(date +%s)


# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true


mkdir -p $MGMT_DB_QUEUE

#python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $MGMT_DB_QUEUE ${REL_NAME} IM_calc running $SLURM_JOB_ID --start_time "$start_time" --nodes $SLURM_NNODES --cores "$SLURM_NTASKS --wct "$WCT"

# Create the results directory if required
mkdir -p $REL_DIR/IM_calc

FD="$(getFromYaml "$REL_DIR/sim_params.yaml" FD_STATLIST)"
if [[ -z "$FD" ]]; then
    echo "❌ FD_STATLIST not found in sim_params.yaml"
    exit 1
else
    echo "FD_STATLIST=$FD"
fi

python $gmsim/workflow/workflow/calculation/verification/im_calc_checkpoint.py $REL_DIR/IM_calc/ `wc -l < ${FD}` 6 --simulated

checkpoint_check=$?

if [[ $checkpoint_check != 0 ]]; then
    # Run the script
    IM_CMD=$(python $SCRIPTS_DIR/run_im_command.py "$REL_DIR")
    echo "Executing: $IM_CMD"
    time eval "$IM_CMD"
else
    echo "No need to computae"
fi
end_time=`date +$runtime_fmt`

# Check that the result files exist
res=0
if [[ ! -f $REL_DIR/IM_calc/${REL_NAME}.csv ]] || [[ ! -f $REL_DIR/IM_calc/${REL_NAME}_imcalc.info ]]; then
    res=1
    echo "IM calculation failed, result files do not exist."
else
    echo "IM calculation appears to have worked"
fi

# Update mgmt_db
# Passed
if [[ $res == 0 ]]; then
    echo "✅ IM completed successfully for $REL_NAME"
    
    timestamp=`date +%Y%m%d_%H%M%S`
 #   python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $MGMT_DB_QUEUE ${REL_NAME} IM_calc completed $SLURM_JOB_ID --end_time "$end_time"

    if [[ ! -d $REL_DIR/ch_log ]]; then
        mkdir $REL_DIR/ch_log
    fi

    fd_name=`python -c "from qcore import utils; params = utils.load_sim_params('$REL_DIR/sim_params.yaml'); print(params['FD_STATLIST'])"`
    fd_count=`cat $fd_name | wc -l`
    pSA_count=`cat $REL_DIR/IM_calc/${REL_NAME}.csv | head -n 1 | grep -o pSA | wc -l`

    # log metadata
    if [[ $checkpoint_check != 0 ]]; then
        python $gmsim/workflow/workflow/automation/metadata/log_metadata.py $REL_DIR IM_calc cores=$SLURM_NTASKS pSA_count=$pSA_count fd_count=$fd_count start_time=$start_time end_time=$end_time status="COMPLETED"
    fi
else
    #failed
  #  python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py $MGMT_DB_QUEUE ${REL_NAME} IM_calc failed $SLURM_JOB_ID --error "$res" --end_time "$end_time"
    echo "❌ IM test failed for $REL_NAME"
fi
