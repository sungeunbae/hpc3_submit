#!/bin/bash

# Exit if no argument is provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

fix_path_script=`dirname $0`/fix_old_nesi_path.sh

input_file="$1"
SUCCESS_CODE=0

while read -r line; do
    [[ -z "$line" ]] && continue

    if [[ ! "$line" =~ ^- ]]; then
        prefix="$line"
        db_path="$prefix/slurm_mgmt.db"
        continue
    fi

    id=$(echo "$line" | sed 's/^- //')

    # Step 1: Update DB
    if [[ -f "$db_path" ]]; then
        # check LF
        if sqlite3 "$db_path" "SELECT status FROM state WHERE run_name='$id' AND proc_type=1;" | grep -q '^5$'; then
            echo "LF is already marked completed (from DB): $prefix/Runs/$id/$id"
        else
            sqlite3 "$db_path" "UPDATE state SET status=5 
                WHERE rowid = (
                    SELECT rowid FROM state 
                    WHERE run_name='$id' AND proc_type=1 
                    ORDER BY id DESC LIMIT 1
                );"
            echo "LF is now marked completed (from DB): $prefix/Runs/$id/$id"
        fi

        #check HF
        if sqlite3 "$db_path" "SELECT status FROM state WHERE run_name='$id' AND proc_type=4;" | grep -q '^5$'; then
            echo "PASS (from DB): $prefix/Runs/$id/$id"
            continue
        fi
    fi

    run_dir="$prefix/Runs/$id/$id/HF/Acc"

    bin_file="$run_dir/HF.bin"
    log_file="$run_dir/HF.log"

    echo "Fix old nesi paths"
    $fix_path_script "$prefix/Runs/$id"

    if [[ ! -s "$bin_file" ]]; then
        echo "!FAIL (missing or empty HF.bin): $run_dir"
        continue
    fi

    if [[ ! -f "$log_file" ]]; then
        echo "!FAIL (missing HF.log): $run_dir"
        continue
    fi

    if ! tail -n 1 "$log_file" | grep -q "Simulation completed"; then
        echo "!FAIL (incomplete simulation): $run_dir"
        continue
    fi

    test_dir="$prefix/Runs/$id/$id"
    res=$($gmsim/workflow/workflow/calculation/verification/test_hf.sh "$test_dir")
    success=$?

    if [[ $success == $SUCCESS_CODE ]]; then
        echo "PASS: $test_dir"

        # Step 4: Update DB
        if [[ -f "$db_path" ]]; then
            sqlite3 "$db_path" "UPDATE state SET status=5 
                WHERE rowid = (
                    SELECT rowid FROM state 
                    WHERE run_name='$id' AND proc_type=4 
                    ORDER BY id DESC LIMIT 1
                );"
            echo "DB updated for $id"
        fi
    else
        echo "!FAIL: $test_dir"
    fi

done < "$input_file"

