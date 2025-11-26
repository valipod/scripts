#!/bin/bash

# This script is now a specialized executor that requires one argument: [jpg|JPG|mp4|mkv|mov|img|video|all].
# If no argument is provided, it defaults to the 'all' mode.

# 1. Capture host environment details
USER_PWD=$(pwd)
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# 2. Define the absolute path to the compose configuration
SCRIPT_DIR="/volume1/docker/exiftool"
FILE_TYPE=$1

# --- New Logic: Check for no parameter and set FILE_TYPE to 'all' ---
if [ -z "$FILE_TYPE" ]; then
    FILE_TYPE="all"
    echo "No file type specified. Running 'all' media processing modes."
fi
# --------------------------------------------------------------------

# 3. Validation
if [ ! -d "$SCRIPT_DIR" ]; then
    echo "Error: ExifTool project directory not found at $SCRIPT_DIR" >&2
    echo "Please edit exiftool.sh and update the SCRIPT_DIR variable." >&2
    exit 1
fi

# 4. Change to the script directory to ensure docker-compose finds the compose.yml
cd "$SCRIPT_DIR" || exit

# --- Define Command Fragments ---
# These fragments are passed to the container's shell.
# Set DateTimeOriginal for images (JPEG format)
JPEG_DATE_CMD='exiftool -n -overwrite_original_in_place -P '\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' '
# Set CreateDate for videos
VIDEO_DATE_CMD='exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' '

# 5. Build the execution script based on the file type
CONTAINER_SCRIPT=""

case "$FILE_TYPE" in
    # Single File Type Execution
    jpg)
        CONTAINER_SCRIPT="exec ${JPEG_DATE_CMD} *.jpg"
        ;;
    JPG)
        CONTAINER_SCRIPT="exec ${JPEG_DATE_CMD} *.JPG"
        ;;
    mp4)
        CONTAINER_SCRIPT="exec ${VIDEO_DATE_CMD} *.mp4"
        ;;
    mkv)
        CONTAINER_SCRIPT="exec ${VIDEO_DATE_CMD} *.mkv"
        ;;
    mov)
        CONTAINER_SCRIPT="exec ${VIDEO_DATE_CMD} *.mov"
        ;;

    # --- BATCH EXECUTION MODES: Execution-Only Echos ---
    img)
        # Process all common image extensions
        CONTAINER_SCRIPT=$(cat <<EOF
COMMANDS_EXECUTED=0
# Check for lowercase jpg files
if ls *.jpg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpg files"; ${JPEG_DATE_CMD} *.jpg ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase jpeg files
if ls *.jpeg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpeg files"; ${JPEG_DATE_CMD} *.jpeg ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase JPG files
if ls *.JPG >/dev/null 2>&1; then echo "-> Executing exiftool for *.JPG files"; ${JPEG_DATE_CMD} *.JPG ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No .jpg or .JPG files found to process." ; fi
EOF
        )
        ;;

    video)
        # Process all common video extensions
        CONTAINER_SCRIPT=$(cat <<EOF
COMMANDS_EXECUTED=0
# Check for lowercase mp4 files
if ls *.mp4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.mp4 files"; ${VIDEO_DATE_CMD} *.mp4 ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MP4 files
if ls *.MP4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.MP4 files"; ${VIDEO_DATE_CMD} *.MP4 ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase mkv files
if ls *.mkv >/dev/null 2>&1; then echo "-> Executing exiftool for *.mkv files"; ${VIDEO_DATE_CMD} *.mkv ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MKV files
if ls *.MKV >/dev/null 2>&1; then echo "-> Executing exiftool for *.MKV files"; ${VIDEO_DATE_CMD} *.MKV ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase mov files
if ls *.mov >/dev/null 2>&1; then echo "-> Executing exiftool for *.mov files"; ${VIDEO_DATE_CMD} *.mov ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MOV files
if ls *.MOV >/dev/null 2>&1; then echo "-> Executing exiftool for *.MOV files"; ${VIDEO_DATE_CMD} *.MOV ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No video files (mp4, mkv, mov) found to process." ; fi
EOF
        )
        ;;
    
    # --- 'ALL' MODE: Combines all image and video checks ---
    all)
        CONTAINER_SCRIPT=$(cat <<EOF
COMMANDS_EXECUTED=0

echo "--- Starting Image Processing ---"
# Check for lowercase jpg files
if ls *.jpg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpg files"; ${JPEG_DATE_CMD} *.jpg ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase jpeg files
if ls *.jpeg >/dev/null 2>&1; then echo "-> Executing exiftool for *.jpeg files"; ${JPEG_DATE_CMD} *.jpeg ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase JPG files
if ls *.JPG >/dev/null 2>&1; then echo "-> Executing exiftool for *.JPG files"; ${JPEG_DATE_CMD} *.JPG ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No image files found to process." ; fi

echo "--- Starting Video Processing ---"
# Check for lowercase mp4 files
if ls *.mp4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.mp4 files"; ${VIDEO_DATE_CMD} *.mp4 ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MP4 files
if ls *.MP4 >/dev/null 2>&1; then echo "-> Executing exiftool for *.MP4 files"; ${VIDEO_DATE_CMD} *.MP4 ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase mkv files
if ls *.mkv >/dev/null 2>&1; then echo "-> Executing exiftool for *.mkv files"; ${VIDEO_DATE_CMD} *.mkv ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MKV files
if ls *.MKV >/dev/null 2>&1; then echo "-> Executing exiftool for *.MKV files"; ${VIDEO_DATE_CMD} *.MKV ; COMMANDS_EXECUTED=1 ; fi
# Check for lowercase mov files
if ls *.mov >/dev/null 2>&1; then echo "-> Executing exiftool for *.mov files"; ${VIDEO_DATE_CMD} *.mov ; COMMANDS_EXECUTED=1 ; fi
# Check for uppercase MOV files
if ls *.MOV >/dev/null 2>&1; then echo "-> Executing exiftool for *.MOV files"; ${VIDEO_DATE_CMD} *.MOV ; COMMANDS_EXECUTED=1 ; fi
if [ "\$COMMANDS_EXECUTED" -eq 0 ]; then echo "No video files found to process." ; fi
EOF
        )
        ;;
    # ---------------------------------
    *)
        echo "Error: Invalid file type specified. Supported types: jpg, JPG, mp4, mkv, mov, img, video, all." >&2
        exit 1
        ;;
esac

# 6. Execute the Docker command
FINAL_CMD="$CONTAINER_SCRIPT"

docker-compose run --rm \
    --user "${HOST_UID}":"${HOST_GID}" \
    -w /data \
    -v "${USER_PWD}":/data \
    exiftool \
    sh -c "$FINAL_CMD"

