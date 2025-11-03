#!/bin/bash

# Use the first argument as the target directory, or default to the current directory (.)
TARGET_DIR="${1:-.}"

# Find specific files (*.sl, *.yaml, e3d.par) and perform replacements
find "$TARGET_DIR" \( -name "*.sl" -o -name "*.yaml" -o -name "e3d.par" \) -type f -exec sed -i '
s|/scale_wlg_nobackup/filesets|/nesi|g;
s|/scale_wlg_persistent/filesets|/nesi|g;
' {} +

echo "Replacement completed in $TARGET_DIR"

