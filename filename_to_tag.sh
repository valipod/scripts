#!/bin/bash

# This script is now a specialized executor that requires one argument: [jpg|mp4].

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

# Define the common regex pattern for YYYY-MM-DD[space or underscore]HH-MM-SS
# The replacement string formats it as 'YYYY:MM:DD HH:MM:SS+03:00'
DATE_TIME_REGEX_PATTERN='\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' '
DATE_TIME_ORIGINAL_REGEX_PATTERN='\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' '

# 5. Define the command based on the file type
case "$FILE_TYPE" in
    jpg)
#        EXIF_CMD='exec exiftool -n -overwrite_original_in_place -a -G1 -s -datetimeoriginal\<filename -d "%Y-%m-%d %H-%M-%S-%%c.jpg" -offsettimeoriginal=+03:00 *.jpg'
#               EXIF_CMD="exec exiftool -n -overwrite_original_in_place -P ${DATE_TIME_ORIGINAL_REGEX_PATTERN} *.jpg"
                EXIF_CMD='exec exiftool -n -overwrite_original_in_place -P '\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.jpg'
        ;;
    JPG)
#        EXIF_CMD='exec exiftool -n -overwrite_original_in_place -a -G1 -s -datetimeoriginal\<filename -d "%Y-%m-%d %H-%M-%S-%%c.JPG" -offsettimeoriginal=+03:00 *.JPG'
                EXIF_CMD='exec exiftool -n -overwrite_original_in_place -P '\''-DateTimeOriginal<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.JPG'
        ;;
    mp4)
        EXIF_CMD='exec exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mp4'
                ;;
    mkv)
        EXIF_CMD='exec exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mkv'
        ;;
    mov)
        EXIF_CMD='exec exiftool -n -overwrite_original_in_place -P '\''-CreateDate<${filename;s/^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2}).*/$1:$2:$3 $4:$5:$6+03:00/}'\'' *.mov'
        ;;
    *)
        # Should be caught by the earlier validation, but here for safety
        echo "Internal Error: Invalid command selected." >&2
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

