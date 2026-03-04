#!/bin/bash
CONTAINER_NAME="exiftool"
CONTAINER_WORK_DIR=$(pwd)

if [ $# -eq 0 ]; then
    echo "Usage: filedate.sh <file>" >&2
    exit 1
fi

docker exec -w "$CONTAINER_WORK_DIR" "$CONTAINER_NAME" exiftool -time:all "$@"