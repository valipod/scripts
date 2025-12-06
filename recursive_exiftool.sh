#!/bin/bash

# --- Configuration ---
EXIFTOOL_SCRIPT="/var/services/homes/dumitval/bin/exiftool.sh"

# Set the root directory for searching
ROOT_DIR="$(pwd)"

# --- Parameter Check and Error Handling ---
TIMEZONE_PARAM="$1"

if [ -z "$TIMEZONE_PARAM" ]; then
    echo "Usage: $0 <timezone>"
    echo "Example: $0 +03:00"
    exit 1
fi

# Check if the existing script is present and executable
if [ ! -x "$EXIFTOOL_SCRIPT" ]; then
    echo "Error: The existing script '$EXIFTOOL_SCRIPT' is missing or not executable."
    echo "Please check the path and permissions."
    exit 1
fi

# --- Main Logic ---

echo "Starting recursive media processing with timezone: $TIMEZONE_PARAM"
echo "Target script: $EXIFTOOL_SCRIPT"
echo "Searching recursively starting from: $ROOT_DIR"
echo "---"

# 1. PROCESS THE CURRENT DIRECTORY ($ROOT_DIR)
echo "-> Processing current directory: $ROOT_DIR"
(
    # We are already in $ROOT_DIR, so just execute the script
    "$EXIFTOOL_SCRIPT" "$TIMEZONE_PARAM"

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

        # Execute the existing script
        "$EXIFTOOL_SCRIPT" "$TIMEZONE_PARAM"

        if [ $? -ne 0 ]; then
            echo "Warning: Script failed in $DIR. (Exit code: $?)"
        fi
    )
    echo "---"
done

echo "Processing complete."
