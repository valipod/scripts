#!/bin/bash

# This script reads EXIF date/time from media files and renames them to a standardized format.
# Only renames files that have non-zero millisecond information in EXIF.
#
# Output format: YYYY-MM-DD HH-mm-ss-SSS.ext
#
# Usage: exif_to_filename.sh <timezone_offset>
# Examples:
#   exif_to_filename.sh 3           # timezone +03:00
#   exif_to_filename.sh -5          # timezone -05:00
#   exif_to_filename.sh +02:00      # timezone +02:00

# --- Define Constants ---
CONTAINER_NAME="exiftool"
CONTAINER_BASE_DIR="/volume1"

# 1. Capture host environment details
CONTAINER_WORK_DIR=$(pwd)

TIMEZONE_OFFSET=$1

# 2. Validation
# Check if a parameter was provided
if [ -z "$TIMEZONE_OFFSET" ]; then
    echo "Error: Missing timezone offset parameter." >&2
    echo "Usage: exif_to_filename.sh <timezone_offset>" >&2
    echo "  timezone_offset: e.g., 3, -5, +02:00, -5:30" >&2
    exit 1
fi

# Normalize timezone offset to +HH:MM or -HH:MM format
# Handle simple integers (e.g., 3 -> +03:00, -5 -> -05:00)
if [[ "$TIMEZONE_OFFSET" =~ ^-?[0-9]{1,2}$ ]]; then
    if [[ "$TIMEZONE_OFFSET" =~ ^- ]]; then
        # Negative number
        num="${TIMEZONE_OFFSET#-}"
        TIMEZONE_OFFSET=$(printf "-%02d:00" "$num")
    else
        # Positive number (no sign or implicit +)
        TIMEZONE_OFFSET=$(printf "+%02d:00" "$TIMEZONE_OFFSET")
    fi
# Handle +N or -N format without minutes (e.g., +3 -> +03:00)
elif [[ "$TIMEZONE_OFFSET" =~ ^[+-][0-9]{1,2}$ ]]; then
    sign="${TIMEZONE_OFFSET:0:1}"
    num="${TIMEZONE_OFFSET:1}"
    TIMEZONE_OFFSET=$(printf "%s%02d:00" "$sign" "$num")
# Handle +HH:MM or -HH:MM format - normalize hours to 2 digits
elif [[ "$TIMEZONE_OFFSET" =~ ^[+-][0-9]{1,2}:[0-9]{2}$ ]]; then
    sign="${TIMEZONE_OFFSET:0:1}"
    rest="${TIMEZONE_OFFSET:1}"
    hours="${rest%%:*}"
    mins="${rest##*:}"
    TIMEZONE_OFFSET=$(printf "%s%02d:%s" "$sign" "$hours" "$mins")
else
    echo "Error: Invalid timezone offset format: $TIMEZONE_OFFSET" >&2
    echo "Please use format like 3, -5, +02:00, or -5:30." >&2
    exit 1
fi

echo "Timezone offset: $TIMEZONE_OFFSET"

# 3. Validation (Directory Check)
# Check if the current path is under the container's global mount point
if [[ "$CONTAINER_WORK_DIR" != /volume1* ]]; then
    echo "Error: Current directory $CONTAINER_WORK_DIR is not under the container's global mount point $CONTAINER_BASE_DIR" >&2
    exit 1
fi

# 3b. Check if .filename marker file exists (skip if already processed)
if [ -f ".filename" ]; then
    echo "Skipping: .filename file exists in $CONTAINER_WORK_DIR (already processed)"
    exit 0
fi

echo "EXIF to Filename Rename Started..."
echo "--------------------------------------------------------"

# 4. Process all media files
shopt -s nullglob nocaseglob

for file in *.jpg *.jpeg *.png *.mp4 *.mov; do
    [ -f "$file" ] || continue

    filename=$(basename "$file")
    extension="${filename##*.}"

    echo "Processing: $filename"

    # Get DateTimeOriginal and SubSecTimeOriginal from EXIF using docker
    exif_data=$(docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -s -s -s -DateTimeOriginal -SubSecTimeOriginal "$file" 2>/dev/null)

    # Parse the output - first line is DateTimeOriginal, second is SubSecTimeOriginal
    datetime=$(echo "$exif_data" | head -1)
    subsec=$(echo "$exif_data" | tail -1)

    # If no DateTimeOriginal, try CreateDate (for videos)
    if [ -z "$datetime" ]; then
        datetime=$(docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -s -s -s -CreateDate "$file" 2>/dev/null)
        subsec=$(docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -s -s -s -SubSecTimeDigitized "$file" 2>/dev/null)
    fi

    if [ -z "$datetime" ]; then
        echo "  -> INFO: No DateTimeOriginal or CreateDate found. Skipping."
        continue
    fi

    # Check if subsec exists and is non-zero
    if [ -z "$subsec" ] || [ "$subsec" = "0" ] || [ "$subsec" = "00" ] || [ "$subsec" = "000" ]; then
        echo "  -> INFO: No non-zero milliseconds found. Skipping."
        continue
    fi

    # Pad subsec to 3 digits
    subsec=$(printf "%03d" "$subsec")

    # Parse datetime: "2024:01:15 10:30:45" -> "2024-01-15 10-30-45"
    # Format: YYYY:MM:DD HH:MM:SS
    if [[ "$datetime" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        hour="${BASH_REMATCH[4]}"
        minute="${BASH_REMATCH[5]}"
        second="${BASH_REMATCH[6]}"

        new_filename="${year}-${month}-${day} ${hour}-${minute}-${second}-${subsec}.${extension,,}"

        if [ "$filename" = "$new_filename" ]; then
            echo "  -> INFO: Already named correctly. Skipping."
            continue
        fi

        # Check if target filename already exists
        if [ -f "$new_filename" ]; then
            echo "  -> WARNING: Target file $new_filename already exists. Skipping."
            continue
        fi

        echo "  -> Renaming to: $new_filename"
        mv "$file" "$new_filename"

        if [ $? -eq 0 ]; then
            echo "  -> Renamed $filename -> $new_filename"

            # Update EXIF with timezone information
            # Build the full datetime with timezone: YYYY:MM:DD HH:MM:SS+HH:MM
            new_datetime="${year}:${month}:${day} ${hour}:${minute}:${second}${TIMEZONE_OFFSET}"

            docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -q -m -P -overwrite_original \
                -DateTimeOriginal="$new_datetime" \
                -CreateDate="$new_datetime" \
                -ModifyDate="$new_datetime" \
                "$new_filename"

            if [ $? -eq 0 ]; then
                echo "  -> ✅ SUCCESS: Updated EXIF with timezone $TIMEZONE_OFFSET"
            else
                echo "  -> ⚠️ WARNING: Renamed but failed to update EXIF timezone"
            fi
        else
            echo "  -> ❌ ERROR: Failed to rename $filename"
        fi
    else
        echo "  -> WARNING: Could not parse datetime format: $datetime"
    fi
done

shopt -u nullglob nocaseglob

# Create .filename marker file to indicate processing is complete
touch .filename
echo "Created .filename marker file in $CONTAINER_WORK_DIR"

echo "--------------------------------------------------------"
echo "Script finished."
