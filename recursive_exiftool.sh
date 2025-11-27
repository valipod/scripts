#!/bin/bash

# --- Configuration ---
EXISTING_SCRIPT="/var/services/homes/dumitval/bin/exiftool.sh"

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
if [ ! -x "$EXISTING_SCRIPT" ]; then
    echo "Error: The existing script '$EXISTING_SCRIPT' is missing or not executable."
    echo "Please check the path and permissions."
    exit 1
fi

# --- Main Logic ---

echo "Starting recursive media processing with timezone: $TIMEZONE_PARAM"
echo "Target script: $EXISTING_SCRIPT"
echo "Searching recursively starting from: $ROOT_DIR"
echo "---"

# 1. PROCESS THE CURRENT DIRECTORY ($ROOT_DIR)
echo "-> Processing current directory: $ROOT_DIR"
(
    # We are already in $ROOT_DIR, so just execute the script
    "$EXISTING_SCRIPT" "$TIMEZONE_PARAM"

    if [ $? -ne 0 ]; then
        echo "Warning: Script failed in $ROOT_DIR. (Exit code: $?)"
    fi
)
echo "---"

# 2. PROCESS ALL SUBDIRECTORIES
# The -mindepth 1 flag is used here to prevent processing $ROOT_DIR a second time.
find "$ROOT_DIR" -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' DIR; do
    echo "-> Entering subdirectory: $DIR"

    # Change into the subdirectory for this iteration
    (
        cd "$DIR" || exit

        # Execute the existing script
        "$EXISTING_SCRIPT" "$TIMEZONE_PARAM"

        if [ $? -ne 0 ]; then
            echo "Warning: Script failed in $DIR. (Exit code: $?)"
        fi
    )
    echo "---"
done

echo "Processing complete."
