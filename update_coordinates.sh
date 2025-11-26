#!/bin/bash

# --- CONFIGURATION ---
# The local directory path containing the XMP files and images.
LOCAL_PHOTO_DIR="."

# --- MAIN SCRIPT LOGIC ---
echo "XMP Sidecar to EXIF Sync Started..."
echo "--------------------------------------------------------"

if ! command -v exiftool &> /dev/null; then
    echo "ERROR: exiftool is not installed. Please install it to continue."
    exit 1
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

    # Base command starts with quality/safety options
    exiftool_options="-q -m -P -overwrite_original"

    # --- A. Handle GPS Coordinates ---
    if [ -n "$RAW_LAT" ] && [ -n "$RAW_LON" ]; then
        LATITUDE_FORMATTED=$(clean_coord "$RAW_LAT")
        LONGITUDE_FORMATTED=$(clean_coord "$RAW_LON")

        echo "  -> XMP Coords: Lat $LATITUDE_FORMATTED, Lon $LONGITUDE_FORMATTED"

        exiftool_options="$exiftool_options -GPSLatitude=\"$LATITUDE_FORMATTED\" -GPSLongitude=\"$LONGITUDE_FORMATTED\""
        GPS_UPDATED=true
    else
        echo "  -> INFO: GPS coordinates not found in $xmp_name."
        GPS_UPDATED=false
    fi

    # --- B. Handle DateTimeOriginal ---
    if [ -n "$RAW_DATE_TIME" ]; then
        # ExifTool can handle the format '2025-09-20T08:45:04.620+03:00' but the EXIF standard doesn't support 
        # the milliseconds (.620) or timezone (+03:00) in DateTimeOriginal.
        # ExifTool automatically cleans this up. We will use the raw string.

        # We also write to CreateDate and ModifyDate for completeness and consistency.
        echo "  -> XMP Date: $RAW_DATE_TIME"

        exiftool_options="$exiftool_options -DateTimeOriginal=\"$RAW_DATE_TIME\" -CreateDate=\"$RAW_DATE_TIME\" -ModifyDate=\"$RAW_DATE_TIME\""
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

    # 5. Use ExifTool to update the image file
    exiftool_command="exiftool $exiftool_options \"$image_file_path\""

    eval "$exiftool_command"

    if [ $? -eq 0 ]; then
        echo "  -> ✅ SUCCESS: Baked data into $image_name."
    else
        echo "  -> ❌ ERROR: ExifTool failed to update $image_name."
    fi

    echo "---"

done

echo "--------------------------------------------------------"
echo "Script finished."
