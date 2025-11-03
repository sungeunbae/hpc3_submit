#!/usr/bin/env bash

# Loop through all expected rlog directories
find . -type d -path "*/LF/Rlog" | while read rlog_dir; do
    # Count total .rlog files
    total=$(find "$rlog_dir" -maxdepth 1 -name "*.rlog" | wc -l)

    # Count how many contain "FINISHED"
    finished=$(grep -l "FINISHED" "$rlog_dir"/*.rlog 2>/dev/null | wc -l)

    # If not all are finished, report the parent {eventname}/{relname}
    if [ "$finished" -lt "$total" ]; then
        # Extract eventname/relname from path
        rel_path=$(dirname "$rlog_dir")  # gives .../{eventname}/{relname}/LF
        echo "${rel_path%/LF}"           # strip trailing /LF
    fi
done
