#!/bin/bash
# script version: slurm
# emod3d slurm script
#

# Please modify this file as needed, this is just a sample
#SBATCH --account=nesi00213
#SBATCH --job-name=lf.$JOBNAME
#SBATCH --partition=genoa
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=168
#SBATCH --time=10:00:00
##SBATCH --mem=420G # maxmem 

set -eou pipefail


## Get the current working directory
SCRIPT_DIR=/nesi/nobackup/nesi00213/RunFolder/submit
REL_DIR="$PWD"
FAULT_DIR=$(dirname "$REL_DIR")

BASE_DIR=$(dirname "$(dirname "$FAULT_DIR")")
echo "REL_DIR=$REL_DIR"
echo "BASE_DIR=$BASE_DIR"


REL_NAME=$(basename "$REL_DIR")
JOBNAME=${REL_NAME:-""}
export gmsim="/nesi/project/nesi00213/Environments/baes2025"
source $gmsim/py311/bin/activate

# Retrieve memory and wall clock time dynamically
MEMORY=${SLURM_MEM_PER_NODE:-"Unknown"}
#WCT=${SLURM_TIMELIMIT:-"Unknown"}
WCT=$(squeue -j "$SLURM_JOB_ID" -h -o "%l")


# Fix old NeSI paths (for this FAULT_DIR recursively, suppress expected warnings)
echo "→ Fixing old NeSI paths for $FAULT_DIR"
$SCRIPTS_DIR/fix_old_nesi_path.sh "$FAULT_DIR" 2>/dev/null || true


# Updating the stats in managementDB
if [[ ! -d "$BASE_DIR/mgmt_db_queue" ]]; then
    mkdir "$BASE_DIR/mgmt_db_queue"
fi

SUCCESS_CODE=0

# Check if e3d.par exists, generate if missing
if [[ ! -f "$REL_DIR/LF/e3d.par" ]]; then
    echo "e3d.par not found, generating..."
    python $gmsim/workflow/workflow/calculation/create_e3d.py "$REL_DIR"
fi

# Ensure MAXMEM is defined, default to 2500 if missing
MAXMEM=${MAXMEM:-2500}

# Verify MAXMEM was properly passed
if [[ -z "${MAXMEM##*2500*}" ]] && [[ "$1" == "" ]]; then
    echo "⚠ WARNING: MAXMEM using default fallback (2500 MB). Check if it was properly exported."
else
    echo "✓ MAXMEM received: $MAXMEM MB/core"
fi

# Update maxmem in e3d.par
sed -i "s/maxmem=.*/maxmem=$MAXMEM/" "$REL_DIR/LF/e3d.par"
echo "e3d.par maxmem updated :$MAXMEM"

# Extract nt value
NT=$(awk -F= '/^nt=/ {print $2}' "$REL_DIR/LF/e3d.par")

if [[ -d "$REL_DIR/LF/Restart" ]] && [[ $(ls -1 "$REL_DIR/LF/Restart" | wc -l) -ne $SUCCESS_CODE ]]; then
    echo "Checkpointed run found, attempting to resume from checkpoint"
    sed -i 's/read_restart=.*/read_restart="1"/' "$REL_DIR/LF/e3d.par"
else
    # This is a fresh run, determine how often to checkpoint
    # Perform calculation: divide by 5 and round to nearest 100
    RESTART_ITINC=$(( (NT / 5 + 50) / 100 * 100 ))

    # Update restart_itinc in e3d.par
    sed -i "s/restart_itinc=.*/restart_itinc=$RESTART_ITINC/" "$REL_DIR/LF/e3d.par"

    echo "Fresh run - Updated restart_itinc in e3d.par to $RESTART_ITINC"
fi

# Print configuration to stdout
echo "#############################################"
echo "Job Configuration:"
echo "Job Name: $JOBNAME"
echo "Nodes: $SLURM_NNODES"
echo "Tasks per Node: $SLURM_NTASKS_PER_NODE"
echo "Memory per Node (sbatch --mem) : $(awk "BEGIN {printf \"%.2f\", $MEMORY / 1024}") GB"
echo "Memory per CPU (e3d.par maxmem): ${MAXMEM} MB"
echo "Wall Clock Time: $WCT"
echo "NT: $NT"
echo "#############################################"

runtime_fmt="%Y-%m-%d_%H:%M:%S"
start_time=$(date +$runtime_fmt)
echo "$start_time"
start_epoch=$(date +%s)

# python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py "$BASE_DIR/mgmt_db_queue" "${SLURM_JOB_ID}" EMOD3D running $SLURM_JOB_ID --start_time "$start_time" --nodes $SLURM_NNODES --cores $SLURM_NTASKS --wct "$WCT"


# Run EMOD3D
srun /nesi/project/nesi00213/opt/hpc3/tools/emod3d-mpi_v3.0.8 -args "par=$REL_DIR/LF/e3d.par"

end_time=$(date +$runtime_fmt)
echo "$end_time"
end_epoch=$(date +%s)

# Calculate the difference
runtime_seconds=$((end_epoch - start_epoch))
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"

ln -sf "$REL_DIR/LF/e3d.par" "$REL_DIR/LF/OutBin/e3d.par"
res=$($gmsim/workflow/workflow/calculation/verification/test_emod3d.sh "$REL_DIR" "$REL_NAME")
success=$?

if [[ $success == $SUCCESS_CODE ]]; then
    sleep 2
    res=$($gmsim/workflow/workflow/calculation/verification/test_emod3d.sh "$REL_DIR" "$REL_NAME")
    success=$?
fi

if [[ $success == $SUCCESS_CODE ]]; then
#    python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py "$BASE_DIR/mgmt_db_queue" "${SLURM_JOB_ID}" EMOD3D completed $SLURM_JOB_ID --end_time "$end_time"
#    rm "$REL_DIR/LF/Restart/*"
#    mkdir -p "$REL_DIR/ch_log"
#    python $gmsim/workflow/workflow/automation/metadata/log_metadata.py "$REL_DIR" EMOD3D cores=$SLURM_NTASKS start_time=$start_time end_time=$end_time status="COMPLETED"
else
    res=$(echo "$res" | tr -d '\n')
 #   python $gmsim/workflow/workflow/automation/execution_scripts/add_to_mgmt_queue.py "$BASE_DIR/mgmt_db_queue" "${SLURM_JOB_ID}" EMOD3D failed $SLURM_JOB_ID --error "$res" --end_time "$end_time"
#    backup_directory="$nobackup/tmp/$USER/${SLURM_JOB_ID}_LF"
#    echo "Completion test failed, moving all files to $backup_directory"
    echo "Completion test failed"
#    mkdir -p "$backup_directory"
#    mv "$REL_DIR/LF/*" "$backup_directory"
fi
