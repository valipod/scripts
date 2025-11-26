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

    # 2. Extract raw coordinates using grep
    RAW_LAT=$(grep -oP '<exif:GPSLatitude>\K[^<]+' "$xmp_file_path")
    RAW_LON=$(grep -oP '<exif:GPSLongitude>\K[^<]+' "$xmp_file_path")

    if [ -z "$RAW_LAT" ] || [ -z "$RAW_LON" ]; then
        echo "  -> INFO: GPS coordinates not found in $xmp_name. Skipping."
        continue
    fi

    # 3. Clean and format the coordinates for ExifTool
    LATITUDE_FORMATTED=$(clean_coord "$RAW_LAT")
    LONGITUDE_FORMATTED=$(clean_coord "$RAW_LON")

    echo "  -> XMP Coords: Lat $LATITUDE_FORMATTED, Lon $LONGITUDE_FORMATTED"

    # 4. Use ExifTool to update the image file
    # CRITICAL CHANGE: Removed -GPSStatus=A to eliminate the warning.
    exiftool_command="exiftool -q -m -P -overwrite_original \
      -GPSLatitude=\"$LATITUDE_FORMATTED\" \
      -GPSLongitude=\"$LONGITUDE_FORMATTED\" \
      \"$image_file_path\""

    eval "$exiftool_command"

    if [ $? -eq 0 ]; then
        echo "  -> ✅ SUCCESS: Baked GPS data into $image_name."
    else
        echo "  -> ❌ ERROR: ExifTool failed to update $image_name."
    fi

    echo "---"

done

echo "--------------------------------------------------------"
echo "Script finished."

