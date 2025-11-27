#!/bin/bash

# --- Configuration ---
EXISTING_SCRIPT="/var/services/homes/dumitval/bin/exiftool.sh"

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
echo "---"

find "$ROOT_DIR" -type d -print0 | while IFS= read -r -d $'\0' DIR; do
    echo "-> Entering directory: $DIR"

    # Change into the directory for this iteration
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
