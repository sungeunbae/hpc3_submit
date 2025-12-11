#!/bin/bash
#SBATCH --account=nesi00213
#SBATCH --job-name=lf.${SLURM_ARRAY_TASK_ID}
#SBATCH --partition=genoa
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=168
#SBATCH --time=10:00:00

set -euo pipefail

# ─── Environment Setup ──────────────────────────────────────────────────────────
export gmsim="/nesi/project/nesi00213/Environments/baes2025"
source "$gmsim/py311/bin/activate"

export PYTHONPATH=$gmsim/workflow:$PYTHONPATH

# ─── Select REL_DIR from DIR_LIST ───────────────────────────────────────────────
REL_DIR=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$DIR_LIST")
cd "$REL_DIR" || { echo "Failed to cd into $REL_DIR"; exit 1; }

REL_NAME=$(basename "$REL_DIR")
FAULT_DIR=$(dirname "$REL_DIR")
BASE_DIR=$(dirname "$(dirname "$FAULT_DIR")")
JOBNAME="$REL_NAME"

echo "REL_DIR=$REL_DIR"
echo "BASE_DIR=$BASE_DIR"

# ─── Resource Info ──────────────────────────────────────────────────────────────
MEMORY=${SLURM_MEM_PER_NODE:-"Unknown"}
WCT=$(squeue -j "$SLURM_JOB_ID" -h -o "%l")
MAXMEM=${MAXMEM:-2500}

echo "✓ MAXMEM received: $MAXMEM MB/core"

# ─── Fix Old NeSI Paths ─────────────────────────────────────────────────────────
SCRIPTS_DIR="/nesi/nobackup/nesi00213/RunFolder/submit"
echo "→ Fixing old NeSI paths for $FAULT_DIR"
"$SCRIPTS_DIR/fix_old_nesi_path.sh" "$FAULT_DIR" 2>/dev/null || true

mkdir -p "$REL_DIR/LF"
# ─── Generate e3d.par if Missing ────────────────────────────────────────────────
if [[ ! -f "$REL_DIR/LF/e3d.par" ]]; then
    echo "e3d.par not found, generating..."
    python "$gmsim/workflow/workflow/calculation/create_e3d.py" "$REL_DIR"
fi

# ─── Update maxmem in e3d.par ───────────────────────────────────────────────────
sed -i "s/maxmem=.*/maxmem=$MAXMEM/" "$REL_DIR/LF/e3d.par"
echo "e3d.par maxmem updated: $MAXMEM"

# ─── Checkpoint Logic ───────────────────────────────────────────────────────────
NT=$(awk -F= '/^nt=/ {print $2}' "$REL_DIR/LF/e3d.par")
SUCCESS_CODE=0

if [[ -d "$REL_DIR/LF/Restart" ]] && [[ $(ls -1 "$REL_DIR/LF/Restart" | wc -l) -ne $SUCCESS_CODE ]]; then
    echo "Checkpointed run found, resuming"
    sed -i 's/read_restart=.*/read_restart="1"/' "$REL_DIR/LF/e3d.par"
else
    RESTART_ITINC=$(( (NT / 5 + 50) / 100 * 100 ))
    sed -i "s/restart_itinc=.*/restart_itinc=$RESTART_ITINC/" "$REL_DIR/LF/e3d.par"
    echo "Fresh run - restart_itinc set to $RESTART_ITINC"
fi

# ─── Print Job Configuration ────────────────────────────────────────────────────
echo "#############################################"
echo "Job Configuration:"
echo "Job Name: $JOBNAME"
echo "Nodes: $SLURM_NNODES"
echo "Tasks per Node: $SLURM_NTASKS_PER_NODE"
echo "Memory per Node: $(awk "BEGIN {printf \"%.2f\", $MEMORY / 1024}") GB"
echo "Memory per CPU: ${MAXMEM} MB"
echo "Wall Clock Time: $WCT"
echo "NT: $NT"
echo "#############################################"

# ─── Run EMOD3D ─────────────────────────────────────────────────────────────────
start_time=$(date +%Y-%m-%d_%H:%M:%S)
start_epoch=$(date +%s)

srun /nesi/project/nesi00213/opt/hpc3/tools/emod3d-mpi_v3.0.8 -args "par=$REL_DIR/LF/e3d.par"

end_time=$(date +%Y-%m-%d_%H:%M:%S)
end_epoch=$(date +%s)
runtime_seconds=$((end_epoch - start_epoch))

echo "$end_time"
echo "Total runtime: $(date -u -d @${runtime_seconds} +%H:%M:%S)"

# ─── Post-run Verification ──────────────────────────────────────────────────────
ln -sf "$REL_DIR/LF/e3d.par" "$REL_DIR/LF/OutBin/e3d.par"
res=$("$gmsim/workflow/workflow/calculation/verification/test_emod3d.sh" "$REL_DIR" "$REL_NAME")
success=$?

if [[ $success == $SUCCESS_CODE ]]; then
    sleep 2
    res=$("$gmsim/workflow/workflow/calculation/verification/test_emod3d.sh" "$REL_DIR" "$REL_NAME")
    success=$?
fi

if [[ $success == $SUCCESS_CODE ]]; then
    echo "✓ EMOD3D verification passed"
else
    res=$(echo "$res" | tr -d '\n')
    echo "⚠ EMOD3D verification failed: $res"
fi

