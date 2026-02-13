#!/bin/bash

# --- CONFIGURATION ---
# The local directory path containing the XMP files and images.
LOCAL_PHOTO_DIR="."

# Docker container configuration
CONTAINER_NAME="exiftool"
CONTAINER_BASE_DIR="/volume1"

# --- MAIN SCRIPT LOGIC ---
echo "XMP Sidecar to EXIF Sync Started..."
echo "--------------------------------------------------------"

# Get the current working directory for docker exec
CONTAINER_WORK_DIR=$(pwd)

# Validate that the current directory is under the container's mount point
if [[ "$CONTAINER_WORK_DIR" != /volume1* ]]; then
    echo "Error: Current directory $CONTAINER_WORK_DIR is not under the container's global mount point $CONTAINER_BASE_DIR" >&2
    exit 1
fi

# Check if .location marker file exists (skip if already processed)
if [ -f ".location" ]; then
    echo "Skipping: .location file exists in $CONTAINER_WORK_DIR (already processed)"
    exit 0
fi

# Function to clean and format coordinates for exiftool
# Changes format from 11,6.6888N to 11 6.6888N (Degrees Minutes Direction)
clean_coord() {
    local raw_coord="$1"
    # Replace the comma with a space (ExifTool expects "Degrees Minutes.Seconds Direction")
    echo "$raw_coord" | sed 's/,/ /g'
}

# Find all .xmp files in the target directory and process them
find "$LOCAL_PHOTO_DIR" -maxdepth 1 -type f -iname "*.xmp" | while IFS= read -r xmp_file_path; do

    # 1. Determine the corresponding image file path
    image_file_path="${xmp_file_path%.xmp}"
    image_name=$(basename "$image_file_path")
    xmp_name=$(basename "$xmp_file_path")

    echo "Processing XMP: $xmp_name"

    if [ ! -f "$image_file_path" ]; then
        echo "  -> WARNING: Image file $image_name not found. Skipping $xmp_name."
        continue
    fi

    # 2. Initialization and Extraction
    # --- GPS Extraction ---
    RAW_LAT=$(grep -oP '<exif:GPSLatitude>\K[^<]+' "$xmp_file_path")
    RAW_LON=$(grep -oP '<exif:GPSLongitude>\K[^<]+' "$xmp_file_path")

    # --- DateTimeOriginal Extraction ---
    # Extract the date/time string from the exif:DateTimeOriginal tag
    RAW_DATE_TIME=$(grep -oP '<exif:DateTimeOriginal>\K[^<]+' "$xmp_file_path")

    # 3. Build the ExifTool Command Dynamically

    # Determine if this is a video file (MP4/MOV can't store EXIF GPS IFD — use XMP instead)
    image_ext="${image_name##*.}"
    image_ext_lower="${image_ext,,}"
    is_video=false
    if [[ "$image_ext_lower" == "mp4" || "$image_ext_lower" == "mov" ]]; then
        is_video=true
    fi

    # Base command starts with quality/safety options
    exiftool_options="-q -m -P -overwrite_original"

    # --- A. Handle GPS Coordinates ---
    if [ -n "$RAW_LAT" ] && [ -n "$RAW_LON" ]; then
        LATITUDE_FORMATTED=$(clean_coord "$RAW_LAT")
        LONGITUDE_FORMATTED=$(clean_coord "$RAW_LON")

        echo "  -> XMP Coords: Lat $LATITUDE_FORMATTED, Lon $LONGITUDE_FORMATTED"

        if [ "$is_video" = true ]; then
            # Video files: write to XMP group (MP4/MOV don't have EXIF GPS IFD)
            exiftool_options="$exiftool_options -xmp:GPSLatitude=\"$LATITUDE_FORMATTED\" -xmp:GPSLongitude=\"$LONGITUDE_FORMATTED\""
        else
            # Image files: write to EXIF GPS IFD
            exiftool_options="$exiftool_options -GPSLatitude=\"$LATITUDE_FORMATTED\" -GPSLongitude=\"$LONGITUDE_FORMATTED\""
        fi
        GPS_UPDATED=true
    else
        echo "  -> INFO: GPS coordinates not found in $xmp_name."
        GPS_UPDATED=false
    fi

    # --- B. Handle DateTimeOriginal ---
    if [ -n "$RAW_DATE_TIME" ]; then
        # XMP format is typically '2025-09-20T08:45:04.620+03:00'
        # Extract milliseconds if present (the digits after the decimal point, before timezone)
        SUBSEC=$(echo "$RAW_DATE_TIME" | grep -oP '\.\K\d{1,3}' | head -1)

        # Extract timezone offset if present (e.g., +03:00, -05:30, Z)
        TZ_OFFSET=$(echo "$RAW_DATE_TIME" | grep -oP '[+-]\d{2}:\d{2}$')

        # We also write to CreateDate and ModifyDate for completeness and consistency.
        echo "  -> XMP Date: $RAW_DATE_TIME"

        exiftool_options="$exiftool_options -DateTimeOriginal=\"$RAW_DATE_TIME\" -CreateDate=\"$RAW_DATE_TIME\" -ModifyDate=\"$RAW_DATE_TIME\""

        # Write subseconds to the appropriate tags if present
        if [ -n "$SUBSEC" ]; then
            echo "  -> XMP SubSec: $SUBSEC"
            exiftool_options="$exiftool_options -SubSecTimeOriginal=\"$SUBSEC\" -SubSecTimeDigitized=\"$SUBSEC\" -SubSecTime=\"$SUBSEC\""
        fi

        # Write timezone offset tags if present
        if [ -n "$TZ_OFFSET" ]; then
            echo "  -> XMP Timezone: $TZ_OFFSET"
            exiftool_options="$exiftool_options -OffsetTime=\"$TZ_OFFSET\" -OffsetTimeOriginal=\"$TZ_OFFSET\" -OffsetTimeDigitized=\"$TZ_OFFSET\""
        fi

        DATE_UPDATED=true
    else
        echo "  -> INFO: DateTimeOriginal not found in $xmp_name."
        DATE_UPDATED=false
    fi

    # 4. Check if any updates are needed
    if [ "$GPS_UPDATED" = false ] && [ "$DATE_UPDATED" = false ]; then
        echo "  -> INFO: No GPS or DateTimeOriginal found. Skipping $xmp_name."
        echo "---"
        continue
    fi

    # 5. Use ExifTool via Docker to update the image file
    exiftool_command="exiftool $exiftool_options \"$image_file_path\""

    docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" sh -c "$exiftool_command"

    if [ $? -eq 0 ]; then
        echo "  -> ✅ SUCCESS: Baked data into $image_name."
    else
        echo "  -> ❌ ERROR: ExifTool failed to update $image_name."
    fi

    echo "---"

done

# Create .location marker file to indicate processing is complete
touch .location
echo "Created .location marker file in $CONTAINER_WORK_DIR"

echo "--------------------------------------------------------"
echo "Script finished."
