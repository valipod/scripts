#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: filedate.sh <file>" >&2
    exit 1
fi
exiftool.sh -time:all "$@"