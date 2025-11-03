#!/bin/bash

input_file="completed_lf_hf.txt"  # Your input file
tar_output="lf_hf.tar.gz"  # TAR file name

# Temporary working list of files to tar
files_to_tar=()

while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{8}_.*$ ]]; then
        run_dir="$line"
    elif [[ "$line" =~ ^- ]]; then
        run_id="${line#- }"
        base_path="$run_dir/Runs/$run_id/$run_id"

        # Add paths to the list
        files_to_tar+=("$base_path/LF/OutBin")
        files_to_tar+=("$base_path/LF/e3d.par")
        files_to_tar+=("$base_path/HF")

        # Check Restart dir
        restart_path="$base_path/LF/Restart"
        if [[ -d "$restart_path" ]]; then
            size=$(du -sb "$restart_path" | cut -f1)
            if [[ "$size" -gt 0 ]]; then
                echo "⚠️  Restart directory has data in: $restart_path ($size bytes)"
                echo "Consider cleaning up before archiving."
            fi
        fi
    fi
done < "$input_file"

# Create TAR
echo "Creating TAR file: $tar_output"
tar -czf "$tar_output" "${files_to_tar[@]}"
echo "Archive created successfully."


