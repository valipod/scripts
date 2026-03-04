#!/bin/bash

# Recursively execute a script in all subdirectories.
#
# Usage: recursive_exiftool.sh <script_name> [script_parameters...]
#
# Examples:
#   recursive_exiftool.sh filename2tag.sh 3          # Write tags if missing, timezone +03:00
#   recursive_exiftool.sh filename2tag.sh -f 3       # Force overwrite, timezone +03:00
#   recursive_exiftool.sh xmp2exif.sh                   # Sync XMP data to EXIF

# Set the root directory for searching
ROOT_DIR="$(pwd)"

# --- Parameter Check and Error Handling ---
SCRIPT_NAME="$1"

if [ -z "$SCRIPT_NAME" ]; then
    echo "Usage: $0 <script_name> [script_parameters...]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 filename_to_tag.sh 3        # Write tags if missing, timezone +03:00" >&2
    echo "  $0 filename_to_tag.sh -f 3     # Force overwrite, timezone +03:00" >&2
    echo "  $0 xmp2exif.sh                 # Sync XMP data to EXIF" >&2
    exit 1
fi

# Shift to get remaining parameters for the target script
shift
SCRIPT_PARAMS=("$@")

# Check if the script exists in PATH
if ! command -v "$SCRIPT_NAME" &> /dev/null; then
    echo "Error: Script '$SCRIPT_NAME' not found in PATH." >&2
    exit 1
fi

# --- Main Logic ---

echo "Starting recursive processing..."
echo "Script: $SCRIPT_NAME"
echo "Parameters: ${SCRIPT_PARAMS[*]}"
echo "Starting from: $ROOT_DIR"
echo "---"

# 1. PROCESS THE CURRENT DIRECTORY ($ROOT_DIR)
echo "-> Processing current directory: $ROOT_DIR"
(
    # We are already in $ROOT_DIR, so just execute the script
    "$SCRIPT_NAME" "${SCRIPT_PARAMS[@]}"

    if [ $? -ne 0 ]; then
        echo "Warning: Script failed in $ROOT_DIR. (Exit code: $?)"
    fi
)
echo "---"

# 2. PROCESS ALL SUBDIRECTORIES
echo "-> Collecting all subdirectories..."

# 1. Use mapfile (or readarray) to safely store all directories into an array.
# This avoids the subshell issue of the find | while pipeline.
mapfile -d $'\0' DIRS < <(find "$ROOT_DIR" -mindepth 1 -type d -print0)

# 2. Iterate through the array of directories
for DIR in "${DIRS[@]}"; do
    # Strip any potential leading/trailing whitespace/null characters from the directory name
    DIR=$(echo "$DIR" | tr -d '\0' | xargs echo -n)

    # Skip empty lines that might result from trimming or bad find output
    if [ -z "$DIR" ]; then
        continue
    fi

    echo "-> Entering subdirectory: $DIR"

    # Use a subshell to change directory, but handle the exit gracefully.
    # The 'exit' is removed to prevent it from killing the main loop.
    (
        if ! cd "$DIR"; then
            echo "Error: Could not enter directory '$DIR'. Skipping."
            exit 1 # Exit the subshell, but the main 'for' loop continues
        fi

        # Execute the script
        "$SCRIPT_NAME" "${SCRIPT_PARAMS[@]}"

        if [ $? -ne 0 ]; then
            echo "Warning: Script failed in $DIR. (Exit code: $?)"
        fi
    )
    echo "---"
done

echo "Processing complete."
