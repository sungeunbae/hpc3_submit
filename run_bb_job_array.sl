#!/bin/bash
#SBATCH --account=nesi00213
#SBATCH --job-name=bb_array
##SBATCH --partition=genoa
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=42
#SBATCH --time=00:10:00
#SBATCH --mem=84G
#SBATCH --array=0-288%5  # Adjust based on the number of lines in bb_targets.txt and concurrency
#SBATCH --output=logs/bb_%A_%a.out
#SBATCH --error=logs/bb_%A_%a.err

#set -eou pipefail

SCRIPTS_DIR=/nesi/nobackup/nesi00213/RunFolder/submit
BASE_DIR=$PWD

TARGET_LIST=${BASE_DIR}/bb_targets.txt
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

BB_BIN="$REL_DIR/BB/Acc/BB.bin"
BB_LOG="$REL_DIR/BB/Acc/BB.log"

if [[ -f "$BB_BIN" && -f "$BB_LOG" && $(grep -c "Simulation completed" "$BB_LOG") -gt 0 ]]; then
    echo "✔ BB already completed for $REL_NAME"
    exit 0
fi

start_time=$(date +"%Y-%m-%d_%H:%M:%S")
start_epoch=$(date +%s)

# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true



# Generate e3d.par if missing
if [[ ! -f "$REL_DIR/LF/e3d.par" ]]; then
    echo "e3d.par not found, generating..."
    cd "$REL_DIR"
    python $gmsim/workflow/workflow/calculation/create_e3d.py "$REL_DIR"
    cd -
fi

mkdir -p "$REL_DIR/BB/Acc"

echo "→ Running BB simulation for $REL_NAME"
srun python $gmsim/workflow/workflow/calculation/bb_sim.py \
    "$REL_DIR/LF/OutBin" \
    "$BASE_DIR/Data/VMs/$REL_NAME" \
    "$REL_DIR/HF/Acc/HF.bin" \
    /nesi/project/nesi00213/StationInfo/geoNet_stats+2023-06-28.vs30 \
    "$REL_DIR/BB/Acc/BB.bin" \
    --flo 1.0 --fmin 0.2 --fmidbot 0.5 --dt 0.005

end_time=$(date +"%Y-%m-%d_%H:%M:%S")
end_epoch=$(date +%s)
runtime_seconds=$((end_epoch - start_epoch))
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"

echo "→ Running BB completion test"
res=$($gmsim/workflow/workflow/calculation/verification/test_bb.sh "$REL_DIR")
success=$?

if [[ "$success" == 0 ]]; then
    echo "✅ BB completed successfully for $REL_NAME"

    mkdir -p "$REL_DIR/ch_log"
    fd_name=$(python -c "from qcore import utils; pb = utils.load_sim_params('$REL_DIR/sim_params.yaml'); print(pb['FD_STATLIST'])")
    fd_count=$(wc -l < "$fd_name")

    python $gmsim/workflow/workflow/automation/metadata/log_metadata.py \
        "$REL_DIR" BB cores=$SLURM_NTASKS fd_count=$fd_count \
        start_time=$start_time end_time=$end_time status="COMPLETED"
else
    echo "❌ BB test failed for $REL_NAME"
    res=$(echo "$res" | tr -d '\n')
    backup_directory="/nesi/nobackup/tmp/$USER/${SLURM_JOB_ID}_${REL_NAME}_BB"
    echo "Moving BB output to $backup_directory"
    mkdir -p "$backup_directory"
    mv "$REL_DIR/BB/"* "$backup_directory"
fi

