#!/bin/bash
# Usage: ./submit_hf_job_array.sh <target_list> [max_parallel=5] [account_label=nesi]
#
# Example:
#   ./submit_hf_job_array.sh part_aa 10 nesi

SCRIPT_DIR=/nesi/nobackup/nesi00213/RunFolder/submit

export gmsim="/nesi/project/nesi00213/Environments/mrd87_4"
source "$gmsim/py311/bin/activate"


# Validate arguments
if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <target_list> [max_parallel=5] [account_label=nesi]"
    echo ""
    echo "Arguments:"
    echo "  target_list    : Path to file containing REL_DIR paths (one per line)"
    echo "  max_parallel   : Maximum concurrent array jobs (default: 5)"
    echo "  account_label  : 'nesi' or 'uc' (default: nesi)"
    echo ""
    echo "Example:"
    echo "  $0 part_aa 10 nesi"
    exit 1
fi

TARGET_LIST=$1
MAX_PARALLEL=${2:-5}
ACCOUNT_LABEL=${3:-nesi}

# Map account label to actual account
case "$ACCOUNT_LABEL" in
    nesi)
        ACCOUNT="nesi00213"
        ;;
    uc)
        ACCOUNT="uc04357"
        ;;
    *)
        echo "Error: Unsupported account label '$ACCOUNT_LABEL'. Use 'nesi' or 'uc'."
        exit 1
        ;;
esac

# Validate target list exists
if [[ ! -f "$TARGET_LIST" ]]; then
    echo "Error: Target list file '$TARGET_LIST' not found"
    exit 1
fi

# Count tasks (subtract 1 because array indices start at 0)
TASK_COUNT=$(($(wc -l < "$TARGET_LIST") - 1))

if [[ $TASK_COUNT -lt 0 ]]; then
    echo "Error: Target list is empty"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Create hf_targets.txt as a symlink or copy to current directory
# This allows the SLURM script to find it as BASE_DIR/hf_targets.txt
if [[ "$TARGET_LIST" != "hf_targets.txt" ]]; then
    if [[ -f "hf_targets.txt" ]]; then
        echo "Warning: hf_targets.txt already exists. Backing up to hf_targets.txt.bak"
        mv hf_targets.txt hf_targets.txt.bak
    fi
    
    # Use absolute path if TARGET_LIST is relative
    if [[ "$TARGET_LIST" != /* ]]; then
        TARGET_LIST="$PWD/$TARGET_LIST"
    fi
    
    ln -s "$TARGET_LIST" hf_targets.txt
    echo "Created symlink: hf_targets.txt -> $TARGET_LIST"
fi

echo "========================================="
echo "HF Job Array Submission"
echo "========================================="
echo "Target list    : $TARGET_LIST"
echo "Number of jobs : $((TASK_COUNT + 1))"
echo "Max parallel   : $MAX_PARALLEL"
echo "Account        : $ACCOUNT"
echo "Array range    : 0-${TASK_COUNT}%${MAX_PARALLEL}"
echo "========================================="

# Submit the job array
sbatch --account="$ACCOUNT" \
       --array=0-${TASK_COUNT}%${MAX_PARALLEL} \
       ${SCRIPT_DIR}/run_hf_job_array.sl

echo ""
echo "Job submitted. Monitor with: squeue -u $USER"
echo "View logs in: $PWD/logs/"
