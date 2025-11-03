#!/bin/bash
# Usage: ./submit_im_array.sh [max_parallel=5]
SCRIPT_DIR=/nesi/nobackup/nesi00213/RunFolder/submit

MAX_PARALLEL=${1:-5} # default : 5
TASK_COUNT=$(($(wc -l < bb_targets.txt) - 1))

cwd=`pwd`

echo "Submitting array job with --array=0-${TASK_COUNT}%${MAX_PARALLEL}"
sbatch --array=0-${TASK_COUNT}%${MAX_PARALLEL} ${SCRIPT_DIR}/run_bb_job_array.sl
