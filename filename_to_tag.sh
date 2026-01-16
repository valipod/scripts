#!/bin/bash

# This script extracts date/time from filenames and writes to EXIF tags.
# By default, only writes tags if missing. Use -f to force overwrite.
#
# Usage: filename_to_tag.sh [-f] <timezone_offset>
# Examples:
#   filename_to_tag.sh +03:00        # Only write if tag is missing
#   filename_to_tag.sh -f +03:00     # Force overwrite existing tags

# --- Define Constants ---
CONTAINER_NAME="exiftool"
CONTAINER_BASE_DIR="/volume1"

# 1. Capture host environment details (Reduced set)
CONTAINER_WORK_DIR=$(pwd)

# 2. Parse parameters
FORCE_OVERWRITE=false

if [ "$1" = "-f" ]; then
    FORCE_OVERWRITE=true
    shift
fi

TIMEZONE_OFFSET=$1

# 3. Validation
# Check if a parameter was provided
if [ -z "$TIMEZONE_OFFSET" ]; then
    echo "Error: Missing timezone offset parameter." >&2
    echo "Usage: filename_to_tag.sh [-f] <timezone_offset>" >&2
    echo "  -f: Force overwrite existing tags (default: only write if missing)" >&2
    echo "  timezone_offset: e.g., 3, -5, +02:00, -5:30" >&2
    exit 1
fi

# Normalize timezone offset to +HH:MM or -HH:MM format

# Normalize timezone offset to +HH:MM or -HH:MM format
case "$TIMEZONE_OFFSET" in
    # Integer (e.g., 3, -5)
    -[0-9]|-[0-9][0-9])
        num="${TIMEZONE_OFFSET#-}"
        TIMEZONE_OFFSET=$(printf "-%02d:00" "$num")
        ;;
    [0-9]|[0-9][0-9])
        TIMEZONE_OFFSET=$(printf "+%02d:00" "$TIMEZONE_OFFSET")
        ;;
    +[0-9]|+[0-9][0-9])
        num="${TIMEZONE_OFFSET#+}"
        TIMEZONE_OFFSET=$(printf "+%02d:00" "$num")
        ;;
    # +HH:MM or -HH:MM
    +[0-9]:[0-9][0-9]|+[0-9][0-9]:[0-9][0-9]|-[0-9]:[0-9][0-9]|-[0-9][0-9]:[0-9][0-9])
        sign="${TIMEZONE_OFFSET:0:1}"
        rest="${TIMEZONE_OFFSET:1}"
        hours="${rest%%:*}"
        mins="${rest##*:}"
        TIMEZONE_OFFSET=$(printf "%s%02d:%s" "$sign" "$hours" "$mins")
        ;;
    *)
        echo "Error: Invalid timezone offset format: $TIMEZONE_OFFSET" >&2
        echo "Please use format like 3, -5, +02:00, or -5:30." >&2
        exit 1
        ;;
esac

echo "Timezone offset: $TIMEZONE_OFFSET"

# 4. Validation (Directory Check)
# Check if the current path is under the container's global mount point
if [[ "$CONTAINER_WORK_DIR" != /volume1* ]]; then
    echo "Error: Current directory $CONTAINER_WORK_DIR is not under the container's global mount point $CONTAINER_BASE_DIR" >&2
    exit 1
fi

# 4b. Check if .time marker file exists (skip if already processed)
if [ -f ".time" ]; then
    echo "Skipping: .time file exists in $CONTAINER_WORK_DIR (already processed)"
    exit 0
fi

# 5. Define Command Fragments
# Double quotes are escaped (\") for execution inside sh -c
# The result is YYYY:MM:DD HH:MM:SS[TIMEZONE_OFFSET]
# Supports filenames with optional milliseconds: YYYY-MM-DD HH-mm-ss[-SSS].ext

# Build the -if condition based on FORCE_OVERWRITE flag
if [ "$FORCE_OVERWRITE" = true ]; then
    JPEG_IF_CONDITION=""
    VIDEO_IF_CONDITION=""
    echo "Mode: Force overwrite (will overwrite existing tags)"
else
    JPEG_IF_CONDITION="-if 'not \$datetimeoriginal' "
    VIDEO_IF_CONDITION="-if 'not \$createdate' "
    echo "Mode: Only write if missing"
fi

# Set DateTimeOriginal for images (JPEG format)
# Use single quotes around the ExifTool substitution block to protect it from the outer shell
# Pattern matches: YYYY-MM-DD[ _]HH-mm-ss[-SSS] where SSS is optional milliseconds
JPEG_DATE_CMD="exiftool -n -overwrite_original_in_place -P '-DateTimeOriginal<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/\$1:\$2:\$3 \$4:\$5:\$6${TIMEZONE_OFFSET}/}' '-CreateDate<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/\$1:\$2:\$3 \$4:\$5:\$6${TIMEZONE_OFFSET}/}' '-SubSecTimeOriginal<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/defined \$8 ? \$8 : \"000\"/ee}' '-SubSecTimeDigitized<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/defined \$8 ? \$8 : \"000\"/ee}' ${JPEG_IF_CONDITION}"

# Set CreateDate for videos
# Use single quotes around the ExifTool substitution block to protect it from the outer shell
VIDEO_DATE_CMD="exiftool -n -overwrite_original_in_place -P '-CreateDate<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/\$1:\$2:\$3 \$4:\$5:\$6${TIMEZONE_OFFSET}/}' '-SubSecTimeDigitized<\${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(-(\d{3}))?.*/defined \$8 ? \$8 : \"000\"/ee}' ${VIDEO_IF_CONDITION}"

# 6. Build the combined execution script ('all' media processing)
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

# Revert to sh -c
docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" sh -c "$FINAL_CMD"

# 9. Create .time marker file to indicate processing is complete
touch .time
echo "Created .time marker file in $CONTAINER_WORK_DIR"

