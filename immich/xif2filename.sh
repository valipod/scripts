#!/bin/bash

# This script reads EXIF date/time from media files and renames them to a standardized format.
# Only renames files that have non-zero millisecond information in EXIF.
#
# Output format: YYYY-MM-DD HH-mm-ss-SSS.ext
#
# Usage: exif_to_filename.sh <timezone_offset> [file]
# Examples:
#   exif_to_filename.sh 3           # all files in current folder, timezone +03:00
#   exif_to_filename.sh -5          # all files in current folder, timezone -05:00
#   exif_to_filename.sh +02:00 image.jpg   # single file

# --- Define Constants ---
CONTAINER_NAME="exiftool"
CONTAINER_BASE_DIR="/volume1"

# 1. Capture host environment details
CONTAINER_WORK_DIR=$(pwd)

TIMEZONE_OFFSET=$1
SINGLE_FILE=$2

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
        TIMEZONE_OFFSET=$(printf -- "-%02d:00" "$num")
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

# 3b. Check if .filename marker file exists (skip if already processed) — only for batch mode
if [ -z "$SINGLE_FILE" ] && [ -f ".filename" ]; then
    echo "Skipping: .filename file exists in $CONTAINER_WORK_DIR (already processed)"
    exit 0
fi

echo "EXIF to Filename Rename Started..."
echo "--------------------------------------------------------"

# 4. Process all media files
shopt -s nullglob nocaseglob

if [ -n "$SINGLE_FILE" ]; then
    file_list=("$SINGLE_FILE")
else
    file_list=(*.jpg *.jpeg *.png *.heic *.mp4 *.mov)
fi

for file in "${file_list[@]}"; do
    [ -f "$file" ] || continue

    filename=$(basename "$file")
    extension="${filename##*.}"

    echo "Processing: $filename"

    # Read all needed tags in one docker exec call
    exif_output=$(docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -s -s \
        -FileTypeExtension -DateTimeOriginal -CreateDate \
        -SubSecTimeOriginal -SubSecTimeDigitized \
        "$file" 2>/dev/null)

    actual_ext=$(echo "$exif_output" | grep "^FileTypeExtension" | sed 's/^[^:]*: //')
    datetime=$(echo "$exif_output" | grep "^DateTimeOriginal" | sed 's/^[^:]*: //')
    subsec=$(echo "$exif_output" | grep "^SubSecTimeOriginal" | sed 's/^[^:]*: //')

    # If no DateTimeOriginal, fall back to CreateDate (for videos)
    if [ -z "$datetime" ]; then
        datetime=$(echo "$exif_output" | grep "^CreateDate" | sed 's/^[^:]*: //')
        subsec=$(echo "$exif_output" | grep "^SubSecTimeDigitized" | sed 's/^[^:]*: //')
    fi
    orig_subsec="$subsec"

    # Detect actual file type (handles e.g. JPEG files with .HEIC extension)
    if [ -n "$actual_ext" ] && [ "${actual_ext,,}" != "${extension,,}" ]; then
        echo "  -> INFO: Extension mismatch — file is ${actual_ext^^} but named .${extension}. Using .${actual_ext,,}."
        extension="$actual_ext"
    fi

    if [ -z "$datetime" ]; then
        echo "  -> INFO: No DateTimeOriginal or CreateDate found. Skipping."
        continue
    fi

    # Check if subsec exists and is non-zero
    has_subsec=true
    if [ -z "$subsec" ] || [ "$subsec" = "0" ] || [ "$subsec" = "00" ] || [ "$subsec" = "000" ]; then
        has_subsec=false
    fi

    # Prepare subsec values only if milliseconds exist
    if [ "$has_subsec" = true ]; then
        # Prepare 3-digit milliseconds for filename
        subsec_filename=$(printf "%-3s" "${subsec:0:3}" | tr ' ' '0')

        # Prepare 6-digit microseconds for EXIF update
        if [[ ${#orig_subsec} -eq 6 && "${orig_subsec:0:3}" == "000" ]]; then
            # If original is 000xyz, correct to xyz000
            subsec_exif="${orig_subsec:3:3}000"
        else
            # Otherwise, pad/truncate to 6 digits
            subsec_exif=$(printf "%-6s" "$orig_subsec" | tr ' ' '0')
            subsec_exif="${subsec_exif:0:6}"
        fi
    fi

    # Parse datetime: "2024:01:15 10:30:45" -> "2024-01-15 10-30-45"
    # Format: YYYY:MM:DD HH:MM:SS
    if [[ "$datetime" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        hour="${BASH_REMATCH[4]}"
        minute="${BASH_REMATCH[5]}"
        second="${BASH_REMATCH[6]}"

        if [ "$has_subsec" = true ]; then
            new_filename="${year}-${month}-${day} ${hour}-${minute}-${second}-${subsec_filename}.${extension,,}"
        else
            new_filename="${year}-${month}-${day} ${hour}-${minute}-${second}.${extension,,}"
        fi

        target_file="$filename"
        renamed=0

        if [ "$filename" != "$new_filename" ]; then
            # Check if target filename already exists
            if [ -f "$new_filename" ]; then
                echo "  -> WARNING: Target file $new_filename already exists. Skipping rename, still updating EXIF."
                # target_file remains "$filename" — EXIF update will still run below
            else
                echo "  -> Renaming to: $new_filename"
                mv "$file" "$new_filename"
                if [ $? -eq 0 ]; then
                    echo "  -> Renamed $filename -> $new_filename"
                    # Check for XMP sidecar file and rename it too
                    xmp_file="${file}.xmp"
                    if [ -f "$xmp_file" ]; then
                        new_xmp_file="${new_filename}.xmp"
                        mv "$xmp_file" "$new_xmp_file"
                        if [ $? -eq 0 ]; then
                            echo "  -> Renamed XMP sidecar: ${filename}.xmp -> ${new_filename}.xmp"
                        else
                            echo "  -> ⚠️ WARNING: Failed to rename XMP sidecar"
                        fi
                    fi
                    target_file="$new_filename"
                    renamed=1
                else
                    echo "  -> ❌ ERROR: Failed to rename $filename"
                    continue
                fi
            fi
        else
            echo "  -> INFO: Already named correctly. Updating EXIF."
        fi

        # Update EXIF with timezone information and corrected subsecond value
        # Build the full datetime with timezone: YYYY:MM:DD HH:MM:SS+HH:MM
        new_datetime="${year}:${month}:${day} ${hour}:${minute}:${second}${TIMEZONE_OFFSET}"

        if [ "$has_subsec" = true ]; then
            docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -q -m -P -overwrite_original \
                -DateTimeOriginal="$new_datetime" \
                -CreateDate="$new_datetime" \
                -ModifyDate="$new_datetime" \
                -SubSecTimeOriginal="$subsec_exif" \
                -SubSecTimeDigitized="$subsec_exif" \
                -SubSecTime="$subsec_exif" \
                -OffsetTime="$TIMEZONE_OFFSET" \
                -OffsetTimeOriginal="$TIMEZONE_OFFSET" \
                -OffsetTimeDigitized="$TIMEZONE_OFFSET" \
                "$target_file"
        else
            docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -q -m -P -overwrite_original \
                -DateTimeOriginal="$new_datetime" \
                -CreateDate="$new_datetime" \
                -ModifyDate="$new_datetime" \
                -OffsetTime="$TIMEZONE_OFFSET" \
                -OffsetTimeOriginal="$TIMEZONE_OFFSET" \
                -OffsetTimeDigitized="$TIMEZONE_OFFSET" \
                "$target_file"
        fi

        if [ $? -eq 0 ]; then
            if [ "$has_subsec" = true ]; then
                echo "  -> ✅ SUCCESS: Updated EXIF with timezone $TIMEZONE_OFFSET and subsecond $subsec_exif"
            else
                echo "  -> ✅ SUCCESS: Updated EXIF with timezone $TIMEZONE_OFFSET (no subsecond)"
            fi
        else
            if [ $renamed -eq 1 ]; then
                echo "  -> ⚠️ WARNING: Renamed but failed to update EXIF timezone/subsecond"
            else
                echo "  -> ⚠️ WARNING: Failed to update EXIF timezone/subsecond"
            fi
        fi
    else
        echo "  -> WARNING: Could not parse datetime format: $datetime"
    fi
done

shopt -u nullglob nocaseglob

# Create .filename marker file to indicate processing is complete (batch mode only)
if [ -z "$SINGLE_FILE" ]; then
    touch .filename
    echo "Created .filename marker file in $CONTAINER_WORK_DIR"
fi
echo "--------------------------------------------------------"
echo "Script finished."
