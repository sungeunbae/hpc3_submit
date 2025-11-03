#!/bin/bash

SLURM_SCRIPT=/nesi/nobackup/nesi00213/RunFolder/submit/run_emod3d.sl

# Hardware specifications for NeSI HPC3
declare -A PARTITION_SPECS=(
    [milan_cores]=126
    [milan_std_mem_gb]=512
    [milan_high_mem_gb]=1024
    [genoa_cores]=166
    [genoa_std_mem_gb]=358
    [genoa_high_mem_gb]=1500
)

# Usage function
usage() {
    cat << EOF
Usage: $0 <job_directory> <nodes> <ntasks_per_node> <mem> <time> [partition] [account_label] [exclusive]

Arguments:
  job_directory      - Path to job directory
  nodes              - Number of nodes
  ntasks_per_node    - Number of tasks (cores) per node
  mem                - Memory per node (e.g., 296G, 512G)
  time               - Wall clock time (e.g., 02:00:00)
  partition          - Optional: 'milan' or 'genoa' (auto-select if not specified)
  account_label      - Optional: 'nesi' or 'uc' (default: nesi)
  exclusive          - Optional: 'yes'/'true' for exclusive mode, 'no'/'false' for shared (default: no)

MAXMEM will be automatically calculated as 80% of available memory per core.

Examples:
  $0 \$(pwd) 1 126 512G 02:00:00 milan nesi yes
  $0 \$(pwd) 2 166 358G 10:00:00 genoa nesi no
  $0 \$(pwd) 1 126 296G 02:00:00                    # Auto-select partition, shared mode
  $0 \$(pwd) 1 126 296G 02:00:00 "" "" yes          # Auto-select partition, exclusive mode
EOF
    exit 1
}

# Function to convert memory string to MB
mem_to_mb() {
    local mem_str=$1
    case ${mem_str: -1} in
        G|g) echo $((${mem_str%?} * 1024)) ;;
        M|m) echo ${mem_str%?} ;;
        T|t) echo $((${mem_str%?} * 1024 * 1024)) ;;
        *)   echo "Error: Invalid memory format '$mem_str'. Use G, M, or T suffix." >&2; exit 1 ;;
    esac
}

# Function to validate partition request
validate_partition() {
    local partition=$1
    local nodes=$2
    local ntasks=$3
    local mem_gb=$4
    
    case $partition in
        milan)
            max_cores=${PARTITION_SPECS[milan_cores]}
            std_mem=${PARTITION_SPECS[milan_std_mem_gb]}
            high_mem=${PARTITION_SPECS[milan_high_mem_gb]}
            ;;
        genoa)
            max_cores=${PARTITION_SPECS[genoa_cores]}
            std_mem=${PARTITION_SPECS[genoa_std_mem_gb]}
            high_mem=${PARTITION_SPECS[genoa_high_mem_gb]}
            ;;
        *)
            echo "Error: Unsupported partition '$partition'. Use 'milan' or 'genoa'." >&2
            exit 1
            ;;
    esac
    
    # Check if cores exceed available
    if (( ntasks > max_cores )); then
        echo "Error: Requested $ntasks cores exceeds $partition maximum of $max_cores cores per node." >&2
        exit 1
    fi
    
    # Check memory per core
    local mem_per_core=$(awk "BEGIN {printf \"%.2f\", $mem_gb / $ntasks}")
    
    if (( $(echo "$mem_per_core < 0.5" | bc -l) )); then
        echo "Warning: Memory per core ($mem_per_core GB) is very low. Minimum recommended is ~1 GB/core." >&2
    fi
    
    if (( $(echo "$mem_per_core > $high_mem / $max_cores" | bc -l) )); then
        echo "Error: Requested $mem_per_core GB/core exceeds $partition maximum of $(awk "BEGIN {printf \"%.2f\", $high_mem / $max_cores}") GB/core." >&2
        exit 1
    fi
    
    # Provide guidance
    if (( $(echo "$mem_gb > $std_mem" | bc -l) )); then
        echo "→ Requesting high memory nodes ($partition high-memory: $(awk "BEGIN {printf \"%.1f\", $high_mem / $max_cores}") GB/core)"
    else
        echo "→ Requesting standard memory nodes ($partition standard: $(awk "BEGIN {printf \"%.1f\", $std_mem / $max_cores}") GB/core)"
    fi
}

# Function to calculate MAXMEM
calculate_maxmem() {
    local mem_mb=$1
    local ntasks=$2
    local safety_factor=0.80  # Use 80% of available per-core memory
    
    local maxmem=$(awk "BEGIN {printf \"%.0f\", ($mem_mb / $ntasks) * $safety_factor}")
    echo $maxmem
}

# Parse arguments
if [[ $# -lt 5 ]] || [[ $# -gt 8 ]]; then
    usage
fi

JOB_DIR=$1
NODES=$2
NTASKS_PER_NODE=$3
MEM=$4
TIME=$5
PARTITION=${6:-""}
ACCOUNT_LABEL=${7:-"nesi"}
EXCLUSIVE=${8:-"no"}

# Normalize exclusive parameter
case "${EXCLUSIVE,,}" in
    yes|true|1)
        EXCLUSIVE_MODE=true
        ;;
    no|false|0|"")
        EXCLUSIVE_MODE=false
        ;;
    *)
        echo "Error: Invalid exclusive option '$EXCLUSIVE'. Use 'yes'/'true' or 'no'/'false'." >&2
        exit 1
        ;;
esac

# Map account label to actual account
case "$ACCOUNT_LABEL" in
    nesi)
        ACCOUNT="nesi00213"
        ;;
    uc)
        ACCOUNT="uc04357"
        ;;
    *)
        echo "Error: Unsupported account label '$ACCOUNT_LABEL'. Use 'nesi' or 'uc'." >&2
        exit 1
        ;;
esac

# Convert memory to MB for calculations
MEM_MB=$(mem_to_mb "$MEM")
MEM_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_MB / 1024}")

# Calculate MAXMEM automatically (80% of available per-core memory)
MAXMEM=$(calculate_maxmem $MEM_MB $NTASKS_PER_NODE)

# Navigate to the job directory
echo "→ Changing directory to: $JOB_DIR"
cd "$JOB_DIR" || { echo "Error: Failed to change directory to $JOB_DIR" >&2; exit 1; }

# Set environment variables
export JOBNAME=$(basename $(realpath "$PWD"))
export MAXMEM

# Validate partition if specified
if [[ -n "$PARTITION" ]]; then
    echo "→ Validating partition: $PARTITION"
    validate_partition "$PARTITION" "$NODES" "$NTASKS_PER_NODE" "$MEM_GB"
    PARTITION_ARG="--partition=$PARTITION"
else
    PARTITION_ARG=""
    echo "→ No partition specified; HPC3 will auto-select based on availability"
fi

# Display job configuration
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Job Configuration:"
echo "  Job Name:              $JOBNAME"
echo "  Nodes:                 $NODES"
echo "  Tasks per Node:        $NTASKS_PER_NODE"
echo "  Total Cores:           $((NODES * NTASKS_PER_NODE))"
echo "  Memory per Node:       $MEM"
echo "  Memory per Core:       $(awk "BEGIN {printf \"%.2f\", $MEM_GB / $NTASKS_PER_NODE}") GB"
echo "  Wall Clock Time:       $TIME"
echo "  Account:               $ACCOUNT"
echo "  MAXMEM (calculated):   $MAXMEM MB/core"
if [[ -n "$PARTITION" ]]; then
    echo "  Partition:             $PARTITION"
fi
if [[ "$EXCLUSIVE_MODE" == "true" ]]; then
    echo "  Exclusive Mode:        YES (--exclusive)"
else
    echo "  Exclusive Mode:        NO (shared)"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""

# Build sbatch command with conditional --exclusive
EXCLUSIVE_ARG=""
if [[ "$EXCLUSIVE_MODE" == "true" ]]; then
    EXCLUSIVE_ARG="--exclusive"
fi

# Display the sbatch command before execution
echo "→ Executing sbatch..."
cmd="sbatch --export=MAXMEM=$MAXMEM,JOBNAME=$JOBNAME --nodes=$NODES --ntasks-per-node=$NTASKS_PER_NODE --mem=$MEM --time=$TIME --account=$ACCOUNT --job-name=$JOBNAME $PARTITION_ARG $EXCLUSIVE_ARG $SLURM_SCRIPT"
echo "  $cmd"
echo ""

$cmd

# Return to the previous directory
cd - > /dev/null

