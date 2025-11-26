#!/bin/bash

# This script is now a specialized executor that requires one argument: [jpg|JPG|mp4|mkv|mov|img|video].

# 1. Capture host environment details
USER_PWD=$(pwd)
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# 2. Define the absolute path to the compose configuration
SCRIPT_DIR="/volume1/docker/exiftool"
IMAGE_NAME="leplusorg/img"
FILE_TYPE=$1

# 3. Validation
if [ ! -d "$SCRIPT_DIR" ]; then
    echo "Error: ExifTool project directory not found at $SCRIPT_DIR" >&2
    echo "Please edit exiftool.sh and update the SCRIPT_DIR variable." >&2
    exit 1
fi

# 4. Change to the script directory to ensure docker-compose finds the compose.yml
cd "$SCRIPT_DIR" || exit

# Define the common ExifTool command fragments using the flexible regex
# NOTE: The entire command is enclosed in single quotes, and the inner 
# single quotes for the -P option are escaped with '\'' (close, escape, open).

# Regex Pattern: s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/
# This supports both 'YYYY-MM-DD HH-MM-SS' and 'YYYY-MM-DD_HH-MM-SS'

# --- COMMAND DEFINITIONS ---

# JPEG commands use the DateTimeOriginal tag
JPEG_LOWER_CMD='exiftool -n -overwrite_original_in_place -P '\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.jpg'
JPEG_UPPER_CMD='exiftool -n -overwrite_original_in_place -P '\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.JPG'

# Video commands use the CreateDate tag
MP4_CMD='exiftool -v -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mp4'
MKV_CMD='exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mkv'
MOV_CMD='exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mov'

# 5. Define the command based on the file type
case "$FILE_TYPE" in
    # Single File Type Execution (Original behavior, using defined variables)
    jpg)
        EXIF_CMD="exec ${JPEG_LOWER_CMD}"
        ;;
    JPG)
        EXIF_CMD="exec ${JPEG_UPPER_CMD}"
        ;;
    mp4)
        EXIF_CMD="exec ${MP4_CMD}"
        ;;
    mkv)
        EXIF_CMD="exec ${MKV_CMD}"
        ;;
    mov)
        EXIF_CMD="exec ${MOV_CMD}"
        ;;

    # --- NEW BATCH EXECUTION MODES ---
    img)
        # Execute both JPEG commands separated by a semicolon (;)
        EXIF_CMD="exec ${JPEG_LOWER_CMD} ; ${JPEG_UPPER_CMD}"
        ;;
    video)
        # Execute all video commands separated by a semicolon (;)
        EXIF_CMD="exec ${MP4_CMD} ; ${MKV_CMD} ; ${MOV_CMD}"
        ;;
    # ---------------------------------

    *)
        echo "Error: Invalid file type specified. Supported types: jpg, JPG, mp4, mkv, mov, img, video." >&2
        exit 1
        ;;
esac

# 6. Execute the Docker command
docker-compose run --rm \
    --user "${HOST_UID}":"${HOST_GID}" \
    -w /data \
    -v "${USER_PWD}":/data \
    exiftool \
    sh -c "$EXIF_CMD"

