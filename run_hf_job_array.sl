#!/bin/bash
#SBATCH --account=nesi00213
#SBATCH --job-name=hf_array
##SBATCH --partition=genoa     # Removed as suggested
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=42
#SBATCH --time=00:05:00         # Increased from 5 to 10 min for safety
#SBATCH --mem=84G
##SBATCH --array=0-309%5 # This will be overridden b sbatch --array parameter
#SBATCH --output=logs/hf_%A_%a.out
#SBATCH --error=logs/hf_%A_%a.err

#set -eou pipefail             # Commented out to prevent early exit on checks

SCRIPTS_DIR=/nesi/nobackup/nesi00213/RunFolder/submit
BASE_DIR=$PWD
TARGET_LIST=$BASE_DIR/hf_targets.txt

export gmsim="/nesi/project/nesi00213/Environments/mrd87_4";
source $gmsim/py311/bin/activate

# Validate target list exists
if [[ ! -f "$TARGET_LIST" ]]; then
    echo "❌ Error: Target list $TARGET_LIST not found"
    exit 1
fi

# Get the directory for this array index
REL_DIR=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$TARGET_LIST")

# Check if REL_DIR is empty (task ID out of range)
if [[ -z "$REL_DIR" ]]; then
    echo "⚠️ SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID is out of range for $TARGET_LIST. Exiting."
    exit 0
fi

REL_NAME=$(basename "$REL_DIR")
FAULT_DIR=$(dirname "$REL_DIR")
MGMT_DB_QUEUE="$BASE_DIR/mgmt_db_queue"

echo "========================================="
echo "HF Array Task: $SLURM_ARRAY_TASK_ID"
echo "REL_DIR  : $REL_DIR"
echo "REL_NAME : $REL_NAME"
echo "========================================="

# Re-enable strict error handling after validation
set -eou pipefail

HF_BIN="$REL_DIR/HF/Acc/HF.bin"
HF_LOG="$REL_DIR/HF/Acc/HF.log"

# Check if already completed
if [[ -f "$HF_BIN" && -f "$HF_LOG" && $(grep -c "Simulation completed" "$HF_LOG" || true) -gt 0 ]]; then
    echo "✔ HF already completed for $REL_NAME"
    exit 0
fi
# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true

mkdir -p "$REL_DIR/HF/Acc" "$MGMT_DB_QUEUE"

runtime_fmt="%Y-%m-%d_%H:%M:%S"
start_time=$(date +$runtime_fmt)
start_epoch=$(date +%s)

echo "→ Running HF simulation for $REL_NAME"
HF_CMD=$(python "$SCRIPTS_DIR/run_hf_command.py" "$REL_DIR")
echo "Executing: $HF_CMD"
eval "$HF_CMD"

end_time=$(date +$runtime_fmt)
end_epoch=$(date +%s)
runtime_seconds=$((end_epoch - start_epoch))
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"

echo "→ Running HF completion test"
res=$($gmsim/workflow/workflow/calculation/verification/test_hf.sh "$REL_DIR")
success=$?

if [[ "$success" == 0 ]]; then
    echo "✅ HF completed successfully for $REL_NAME"
    
    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py \
        "$MGMT_DB_QUEUE" "$REL_NAME" HF completed "$SLURM_JOB_ID" --end_time "$end_time"

    mkdir -p "$REL_DIR/ch_log"
    fd_name=$(python -c "from qcore import utils; p = utils.load_sim_params('$REL_DIR/sim_params.yaml'); print(p['FD_STATLIST'])")
    fd_count=$(wc -l < "$fd_name")

    python $gmsim/workflow/workflow/automation/metadata/log_metadata.py \
        "$REL_DIR" HF cores=$SLURM_NTASKS fd_count=$fd_count \
        start_time=$start_time end_time=$end_time status="COMPLETED"
else
    echo "❌ HF test failed for $REL_NAME"
    res=$(echo "$res" | tr -d '\n')
    
    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py \
        "$MGMT_DB_QUEUE" "$REL_NAME" HF failed "$SLURM_JOB_ID" --error "$res" --end_time "$end_time"

    backup_directory="/nesi/nobackup/tmp/$USER/${SLURM_JOB_ID}_${REL_NAME}_HF"
    echo "Moving HF output to $backup_directory"
    mkdir -p "$backup_directory"
    mv "$REL_DIR/HF/"* "$backup_directory"
fi
