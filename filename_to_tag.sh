#!/bin/bash

# This script now requires a single parameter: the timezone offset (e.g., +3, -5, +02:00).
# Example execution: exiftool.sh +03:00

# 1. Capture host environment details
USER_PWD=$(pwd)
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# 2. Get the timezone offset parameter
TIMEZONE_OFFSET=$1

# 3. Validation
# Check if a parameter was provided
if [ -z "$TIMEZONE_OFFSET" ]; then
    echo "Error: Missing timezone offset parameter." >&2
    echo "Usage: exiftool.sh [+HH] or exiftool.sh [+HH:MM]" >&2
    exit 1
fi

# Ensure the timezone offset is in a valid format (e.g., +3, -05, +02:00, -5:30)
# This checks for a sign (+ or -) followed by digits, optionally with a colon and more digits.
if ! [[ "$TIMEZONE_OFFSET" =~ ^[+-][0-9]{1,2}(:[0-9]{2})?$ ]]; then
    echo "Error: Invalid timezone offset format: $TIMEZONE_OFFSET" >&2
    echo "Please use format like +3, -05, +02:00, or -5:30." >&2
    exit 1
fi

# 4. Define the absolute path to the compose configuration
SCRIPT_DIR="/volume1/docker/exiftool"

# 5. Validation (Directory Check)
if [ ! -d "$SCRIPT_DIR" ]; then
    echo "Error: ExifTool project directory not found at $SCRIPT_DIR" >&2
    echo "Please edit exiftool.sh and update the SCRIPT_DIR variable." >&2
    exit 1
fi

# 6. Change to the script directory to ensure docker-compose finds the compose.yml
cd "$SCRIPT_DIR" || exit

# --- Define Command Fragments ---
# The filename pattern is (\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}) which matches
# 'YYYY-MM-DD HH-MM-SS' or 'YYYY-MM-DD_HH-MM-SS'
# The result is YYYY:MM:DD HH:MM:SS[TIMEZONE_OFFSET]

# Set DateTimeOriginal for images (JPEG format)
JPEG_DATE_CMD="exiftool -n -overwrite_original_in_place -P '-DateTimeOriginal<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/\$1:\$2:\$3 \$4:\$5:\$6${TIMEZONE_OFFSET}/}' "

# Set CreateDate for videos
VIDEO_DATE_CMD="exiftool -n -overwrite_original_in_place -P '-CreateDate<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/\$1:\$2:\$3 \$4:\$5:\$6${TIMEZONE_OFFSET}/}' "

# 7. Build the combined execution script ('all' media processing)
CONTAINER_SCRIPT=$(cat <<EOF
COMMANDS_EXECUTED=0

echo "--- Starting Image Processing (Timezone: ${TIMEZONE_OFFSET}) ---"
# Check for lowercase png files
if ls *.png >/dev/null 2>&1; then echo "-> Executing exiftool for *.png files"; ${JPEG_DATE_CMD} *.png ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase jpg files
if ls *.jpg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpg files"; ${JPEG_DATE_CMD} *.jpg ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase jpeg files
if ls *.jpeg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpeg files"; ${JPEG_DATE_CMD} *.jpeg ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase JPG files
if ls *.JPG >/dev/null 2>&1; then echo "-> Executing exiftool for *.JPG files"; ${JPEG_DATE_CMD} *.JPG ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No image files found to process (jpg, jpeg, png)." ; fi

echo "--- Starting Video Processing (Timezone: ${TIMEZONE_OFFSET}) ---"
# Check for lowercase mp4 files
if ls *.mp4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.mp4 files"; ${VIDEO_DATE_CMD} *.mp4 ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MP4 files
if ls *.MP4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.MP4 files"; ${VIDEO_DATE_CMD} *.MP4 ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase mov files
if ls *.mov >/dev/null 2>&1; then echo "-> Executing exiftool for *.mov files"; ${VIDEO_DATE_CMD} *.mov ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MOV files
if ls *.MOV >/dev/null 2>&1; then echo "-> Executing exiftool for *.MOV files"; ${VIDEO_DATE_CMD} *.MOV ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No video files found to process (mp4, mov)." ; fi
EOF
)

# 8. Execute the Docker command
FINAL_CMD="$CONTAINER_SCRIPT"

docker-compose run --rm -T \
    --user "${HOST_UID}":"${HOST_GID}" \
    -w /data \
    -v "${USER_PWD}":/data \
    exiftool \
    sh -c "$FINAL_CMD"

