#!/bin/bash

SLURM_SCRIPT=/nesi/nobackup/nesi00213/RunFolder/submit/run_bb.sl
# Ensure at least six arguments are provided
if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
    echo "Usage: $0 <job_directory> <nodes> <ntasks_per_node> <mem> <time> [account_label]"
    exit 1
fi

# Assign arguments to variables
JOB_DIR=$1
NODES=$2
NTASKS_PER_NODE=$3
MEM=$4
TIME=$5
ACCOUNT_LABEL=${6:-nesi}  # Defaults to "nesi" if not provided

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

# Navigate to the job directory
echo "Changing directory to: $JOB_DIR"
cd "$JOB_DIR" || { echo "Failed to change directory to $JOB_DIR"; exit 1; }

# Set environment variables
export JOBNAME=$(basename "$PWD")

# Display the sbatch command before execution
echo "Executing sbatch with the following parameters:"
cmd="sbatch --nodes=$NODES --ntasks-per-node=$NTASKS_PER_NODE --mem=$MEM --time=$TIME --account=$ACCOUNT --job-name=$JOBNAME $SLURM_SCRIPT"
echo $cmd
eval $cmd

# Return to the previous directory
cd -

