#!/usr/bin/env bash
# ==============================================================
# monitor_batch.sh
# Generic Slurm array monitor/launcher for batch lists.
#
# Usage (positional args):
#   monitor_batch.sh <runs_dir> <submit_script> <job_name> <max_parallel> <account> <target_link> <batch_glob>
#
# Example:
#   monitor_batch.sh \
#     /nesi/nobackup/nesi00213/RunFolder/sjn87/Objective2/NZ/AllEvents/Runs \
#     /nesi/nobackup/nesi00213/RunFolder/submit/submit_hf_job_array.sh \
#     hf_array 10 nesi \
#     hf_targets.txt 'part_*'
#
# Safe to run under cron/scron every 30 minutes.
# ==============================================================

set -euo pipefail

if [[ $# -lt 7 ]]; then
  echo "Usage: $0 <runs_dir> <submit_script> <job_name> <max_parallel> <account> <target_link> <batch_glob>" >&2
  exit 1
fi

RUNS_DIR="$1"
SUBMIT="$2"
JOB_NAME="$3"
MAX_PARALLEL="$4"
ACCOUNT="$5"
TARGET_LINK="$6"   # e.g., hf_targets.txt (symlink)
BATCH_GLOB="$7"    # e.g., 'part_*'

LOCKFILE="/tmp/monitor_${JOB_NAME}_$(basename "${TARGET_LINK}").lock"
LOG="${RUNS_DIR}/logs/monitor_${JOB_NAME}.log"

mkdir -p "${RUNS_DIR}/logs"

# Prevent overlapping executions
exec 9>"${LOCKFILE}"
if ! flock -n 9; then
  echo "$(date -Is)  [SKIP] another monitor for ${JOB_NAME}/${TARGET_LINK} is running" >> "${LOG}"
  exit 0
fi

cd "${RUNS_DIR}"

# 1) Is this array already running/pending?
if squeue -u "${USER}" -h -n "${JOB_NAME}" | grep -q .; then
  echo "$(date -Is)  [OK] ${JOB_NAME} present in squeue; nothing to do." >> "${LOG}"
  exit 0
fi

# 2) Determine "current" and "next" batch from generic args
if [[ ! -L "${TARGET_LINK}" ]]; then
  echo "$(date -Is)  [ERR] ${TARGET_LINK} missing or not a symlink." >> "${LOG}"
  exit 1
fi

current_target="$(readlink -f -- "${TARGET_LINK}")"
current_base="$(basename -- "${current_target}")"

# Build sorted list from pattern (avoid parsing ls; use compgen)
mapfile -t parts < <(compgen -G "${BATCH_GLOB}" | sort)
if [[ ${#parts[@]} -eq 0 ]]; then
  echo "$(date -Is)  [ERR] no files match ${BATCH_GLOB} in ${RUNS_DIR}" >> "${LOG}"
  exit 1
fi

# Find the next item strictly after current_base
next_batch=""
for i in "${!parts[@]}"; do
  if [[ "${parts[$i]}" == "${current_base}" ]]; then
    next_index=$(( i + 1 ))
    if (( next_index < ${#parts[@]} )); then
      next_batch="${parts[$next_index]}"
    fi
    break
  fi
done

# If current_base isn't in the list (e.g., first run or renamed),
# pick the first item that sorts AFTER current_base; otherwise do nothing if at end.
if [[ -z "${next_batch}" ]]; then
  for p in "${parts[@]}"; do
    if [[ "${p}" > "${current_base}" ]]; then
      next_batch="${p}"
      break
    fi
  done
fi

if [[ -z "${next_batch}" ]]; then
  echo "$(date -Is)  [DONE] nothing to submit (likely already at the last batch). Current=${current_base}" >> "${LOG}"
  exit 0
fi

# 3) Submit next batch
echo "$(date -Is)  [RUN] submitting ${next_batch}" >> "${LOG}"
{
  set -x
  "${SUBMIT}" "${next_batch}" "${MAX_PARALLEL}" "${ACCOUNT}"
  set +x
} >> "${LOG}" 2>&1
echo "$(date -Is)  [OK] submitted ${next_batch}" >> "${LOG}"

