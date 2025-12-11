#!/usr/bin/env bash
set -euo pipefail

# ─── Argument Parsing ───────────────────────────────────────────────────────────
if [[ $# -lt 5 || $# -gt 9 ]]; then
  echo "Usage: $0 <base_event_dir> <nodes> <ntasks_per_node> <mem> <time> [partition] [account_label] [exclusive] [exclude_list]"
  exit 1
fi

BASE_DIR="$1"
NODES="$2"
NTASKS_PER_NODE="$3"
MEM="$4"
TIME="$5"
PARTITION="${6:-""}"
ACCOUNT_LABEL="${7:-nesi}"
EXCLUSIVE="${8:-no}"
EXCLUDE_LIST="${9:-""}"  # comma-separated RELs to exclude

# ─── Account Mapping ────────────────────────────────────────────────────────────
case "$ACCOUNT_LABEL" in
  nesi) ACCOUNT="nesi00213" ;;
  uc)   ACCOUNT="uc04357" ;;
  *) echo "Error: Unsupported account label '$ACCOUNT_LABEL'."; exit 1 ;;
esac

# ─── Exclusive Mode ─────────────────────────────────────────────────────────────
case "${EXCLUSIVE,,}" in
  yes|true|1) EXCLUSIVE_ARG="--exclusive" ;;
  no|false|0|"") EXCLUSIVE_ARG="" ;;
  *) echo "Error: Invalid exclusive option '$EXCLUSIVE'."; exit 1 ;;
esac

# ─── Partition Specs ────────────────────────────────────────────────────────────
declare -A PARTITION_SPECS=(
  [milan_cores]=126
  [milan_std_mem_gb]=512
  [milan_high_mem_gb]=1024
  [genoa_cores]=166
  [genoa_std_mem_gb]=358
  [genoa_high_mem_gb]=1500
)

if [[ -n "$PARTITION" ]]; then
  case "$PARTITION" in
    milan) max_cores=${PARTITION_SPECS[milan_cores]}; std_mem=${PARTITION_SPECS[milan_std_mem_gb]}; high_mem=${PARTITION_SPECS[milan_high_mem_gb]} ;;
    genoa) max_cores=${PARTITION_SPECS[genoa_cores]}; std_mem=${PARTITION_SPECS[genoa_std_mem_gb]}; high_mem=${PARTITION_SPECS[genoa_high_mem_gb]} ;;
    *) echo "Error: Unsupported partition '$PARTITION'."; exit 1 ;;
  esac
  if (( NTASKS_PER_NODE > max_cores )); then echo "Error: Too many cores."; exit 1; fi
  PARTITION_ARG="--partition=$PARTITION"
else
  PARTITION_ARG=""
fi

# ─── Memory Conversion ──────────────────────────────────────────────────────────
mem_to_mb() {
  case ${1: -1} in
    G|g) echo $((${1%?} * 1024)) ;;
    M|m) echo ${1%?} ;;
    T|t) echo $((${1%?} * 1024 * 1024)) ;;
    *) echo "Error: Invalid memory format '$1'."; exit 1 ;;
  esac
}
MEM_MB=$(mem_to_mb "$MEM")
MAXMEM=$(awk "BEGIN {printf \"%.0f\", ($MEM_MB / $NTASKS_PER_NODE) * 0.80}")

# ─── Build Directory List ───────────────────────────────────────────────────────
FAULT=$(basename "$BASE_DIR")
DIR_LIST="${BASE_DIR%/}/.sim_dirs.list"
> "$DIR_LIST"


# Function to check if a run is successfully finished
is_completed() {
    local dir="$1"
    local name="$2"
    # Construct rlog path: e.g., AwatereSW_REL21/LF/Rlog/AwatereSW_REL21-00000.rlog
    local rlog="$dir/LF/Rlog/${name}-00000.rlog"

    if [[ -f "$rlog" ]]; then
        # Check if the specific success message exists in the file
        if grep -q "PROGRAM emod3d-mpi IS FINISHED" "$rlog"; then
            return 0 # True (Completed)
        fi
    fi
    return 1 # False (Not completed)
}
# 1. Check Median
MEDIAN_DIR="$BASE_DIR/$FAULT"
if [[ -f "$MEDIAN_DIR/sim_params.yaml" ]]; then
    if is_completed "$MEDIAN_DIR" "$FAULT"; then
        echo "→ Skipping completed Median ($FAULT)"
    else
        echo "$MEDIAN_DIR" >> "$DIR_LIST"
    fi
fi

# 2. Check RELs
find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -name "${FAULT}_REL*" | sort | while read -r dir; do
  REL_NAME=$(basename "$dir")
  REL_ID="${REL_NAME##*_}"  # Extract REL01, REL02, etc.

  # Check Exclude List
  if [[ ",$EXCLUDE_LIST," == *",$REL_ID,"* ]]; then
    echo "→ Skipping excluded $REL_NAME"
    continue
  fi

  # Check Success Marker (Rlog content)
  if is_completed "$dir" "$REL_NAME"; then
    echo "→ Skipping completed $REL_NAME (Found success in rlog)"
    continue
  fi

  # Add to list if valid sim
  if [[ -f "$dir/sim_params.yaml" ]]; then
    echo "$dir" >> "$DIR_LIST"
  fi
done


NUM_DIRS=$(wc -l < "$DIR_LIST")
if [[ "$NUM_DIRS" -eq 0 ]]; then echo "No sim_params.yaml found (or all completed)."; exit 1; fi

echo "Found $NUM_DIRS runs remaining for $FAULT. Submitting job array..."

# ─── Submit Job Array ───────────────────────────────────────────────────────────
sbatch \
  --array=0-$((NUM_DIRS - 1)) \
  --nodes="$NODES" \
  --ntasks-per-node="$NTASKS_PER_NODE" \
  --mem="$MEM" \
  --time="$TIME" \
  $PARTITION_ARG \
  --account="$ACCOUNT" \
  $EXCLUSIVE_ARG \
  --job-name="lf.${FAULT}" \
  --export=ALL,DIR_LIST="$DIR_LIST",MAXMEM="$MAXMEM" \
  /nesi/nobackup/nesi00213/RunFolder/submit/run_emod3d_array.sl

