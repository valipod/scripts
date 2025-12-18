#!/bin/bash

# This script executes exiftool commands inside the exiftool docker container.
# The working directory is automatically set to the current folder.
#
# Usage: exif.sh <exiftool_command>
# Examples:
#   exif.sh -s -time:all "2023-11-06 17-04-57-614.jpg"
#   exif.sh -G1 -a -s myfile.jpg
#   exif.sh -DateTimeOriginal -SubSecTimeOriginal *.jpg

# --- Define Constants ---
CONTAINER_NAME="exiftool"

# Capture current working directory
CONTAINER_WORK_DIR=$(pwd)

# Validation
if [ $# -eq 0 ]; then
    echo "Error: No exiftool command provided." >&2
    echo "Usage: exif.sh <exiftool_command>" >&2
    echo "Examples:" >&2
    echo "  exif.sh -s -time:all \"filename.jpg\"" >&2
    echo "  exif.sh -G1 -a -s myfile.jpg" >&2
    exit 1
fi

# Execute exiftool in the container with all passed arguments
docker exec -w "$CONTAINER_WORK_DIR" "$CONTAINER_NAME" exiftool "exiftool $@"
