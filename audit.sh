#!/bin/bash

# This script audits media files by comparing EXIF metadata against expected values.
# Checks timezone offset consistency and filename-to-EXIF datetime agreement.
# Read-only audit — no files are modified.
#
# Usage: audit.sh <timezone_offset>
# Examples:
#   audit.sh 3           # expected timezone +03:00
#   audit.sh -5          # expected timezone -05:00
#   audit.sh +02:00      # expected timezone +02:00

# --- Define Constants ---
CONTAINER_NAME="exiftool"
CONTAINER_BASE_DIR="/volume1"

# 1. Capture host environment details
CONTAINER_WORK_DIR=$(pwd)

TIMEZONE_OFFSET=$1

# 2. Validation
if [ -z "$TIMEZONE_OFFSET" ]; then
    echo "Error: Missing timezone offset parameter." >&2
    echo "Usage: audit.sh <timezone_offset>" >&2
    echo "  timezone_offset: e.g., 3, -5, +02:00, -5:30" >&2
    exit 1
fi

# Normalize timezone offset to +HH:MM or -HH:MM format
case "$TIMEZONE_OFFSET" in
    -[0-9]|-[0-9][0-9])
        num="${TIMEZONE_OFFSET#-}"
        TIMEZONE_OFFSET=$(printf "-%02d:00" "$num")
        ;;
    [0-9]|[0-9][0-9])
        TIMEZONE_OFFSET=$(printf "+%02d:00" "$TIMEZONE_OFFSET")
        ;;
    +[0-9]|+[0-9][0-9])
        num="${TIMEZONE_OFFSET#+}"
        TIMEZONE_OFFSET=$(printf "+%02d:00" "$num")
        ;;
    +[0-9]:[0-9][0-9]|+[0-9][0-9]:[0-9][0-9]|-[0-9]:[0-9][0-9]|-[0-9][0-9]:[0-9][0-9])
        sign="${TIMEZONE_OFFSET:0:1}"
        rest="${TIMEZONE_OFFSET:1}"
        hours="${rest%%:*}"
        mins="${rest##*:}"
        TIMEZONE_OFFSET=$(printf "%s%02d:%s" "$sign" "$hours" "$mins")
        ;;
    *)
        echo "Error: Invalid timezone offset format: $TIMEZONE_OFFSET" >&2
        echo "Please use format like 3, -5, +02:00, or -5:30." >&2
        exit 1
        ;;
esac

echo "Expected timezone offset: $TIMEZONE_OFFSET"

# 3. Validation (Directory Check)
if [[ "$CONTAINER_WORK_DIR" != /volume1* ]]; then
    echo "Error: Current directory $CONTAINER_WORK_DIR is not under the container's global mount point $CONTAINER_BASE_DIR" >&2
    exit 1
fi

echo "Audit Started..."
echo "--------------------------------------------------------"

# 4. Initialize counters
total_files=0
files_with_issues=0
tz_mismatch_count=0
missing_tz_count=0
datetime_mismatch_count=0
subsec_mismatch_count=0
no_exif_date_count=0
unparseable_name_count=0

# 5. Process all media files
shopt -s nullglob nocaseglob

for file in *.jpg *.jpeg *.png *.mp4 *.mov; do
    [ -f "$file" ] || continue

    ((total_files++))

    filename=$(basename "$file")
    issues=()

    # --- Read all EXIF tags in one docker exec call ---
    exif_output=$(docker exec -w "${CONTAINER_WORK_DIR}" "${CONTAINER_NAME}" exiftool -s -s \
        -DateTimeOriginal -CreateDate \
        -SubSecTimeOriginal -SubSecTimeDigitized \
        -OffsetTimeOriginal \
        "$file" 2>/dev/null)

    # Parse the output (format: "TagName                 : Value")
    exif_datetime=$(echo "$exif_output" | grep "^DateTimeOriginal" | sed 's/^[^:]*: //')
    exif_createdate=$(echo "$exif_output" | grep "^CreateDate" | sed 's/^[^:]*: //')
    exif_subsec=$(echo "$exif_output" | grep "^SubSecTimeOriginal" | sed 's/^[^:]*: //')
    exif_subsec_digitized=$(echo "$exif_output" | grep "^SubSecTimeDigitized" | sed 's/^[^:]*: //')
    exif_tz=$(echo "$exif_output" | grep "^OffsetTimeOriginal" | sed 's/^[^:]*: //')

    # Prefer DateTimeOriginal, fall back to CreateDate for videos
    effective_datetime="$exif_datetime"
    effective_subsec="$exif_subsec"
    if [ -z "$effective_datetime" ]; then
        effective_datetime="$exif_createdate"
        effective_subsec="$exif_subsec_digitized"
    fi

    # --- Check timezone offset ---
    if [ -z "$exif_tz" ]; then
        issues+=("MISSING TIMEZONE: OffsetTimeOriginal not set (expected $TIMEZONE_OFFSET)")
        ((missing_tz_count++))
    elif [ "$exif_tz" != "$TIMEZONE_OFFSET" ]; then
        issues+=("TIMEZONE MISMATCH: found '$exif_tz', expected '$TIMEZONE_OFFSET'")
        ((tz_mismatch_count++))
    fi

    # --- Parse the filename and compare with EXIF ---
    if [[ "$filename" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2})-([0-9]{2})-([0-9]{2})(-([0-9]{3}))?\.([a-zA-Z0-9]+)$ ]]; then
        fn_year="${BASH_REMATCH[1]}"
        fn_month="${BASH_REMATCH[2]}"
        fn_day="${BASH_REMATCH[3]}"
        fn_hour="${BASH_REMATCH[4]}"
        fn_min="${BASH_REMATCH[5]}"
        fn_sec="${BASH_REMATCH[6]}"
        fn_subsec="${BASH_REMATCH[8]}"

        fn_datetime="${fn_year}:${fn_month}:${fn_day} ${fn_hour}:${fn_min}:${fn_sec}"

        if [ -z "$effective_datetime" ]; then
            issues+=("NO EXIF DATE: no DateTimeOriginal or CreateDate found")
            ((no_exif_date_count++))
        else
            # Strip timezone suffix if present (e.g., "2025:12:23 11:43:58+08:00" -> "2025:12:23 11:43:58")
            exif_datetime_bare="${effective_datetime%[+-]*}"

            # Compare date+time portion
            if [ "$fn_datetime" != "$exif_datetime_bare" ]; then
                issues+=("DATETIME MISMATCH: filename='$fn_datetime', EXIF='$exif_datetime_bare'")
                ((datetime_mismatch_count++))
            elif [ -n "$fn_subsec" ]; then
                # Date+time match — compare subseconds if filename has them
                normalized_exif_subsec=""
                if [ -n "$effective_subsec" ]; then
                    normalized_exif_subsec=$(printf "%-3s" "${effective_subsec:0:3}" | tr ' ' '0')
                fi

                if [ "$fn_subsec" != "$normalized_exif_subsec" ]; then
                    issues+=("SUBSEC MISMATCH: filename='$fn_subsec', EXIF='$effective_subsec' (normalized: '$normalized_exif_subsec')")
                    ((subsec_mismatch_count++))
                fi
            fi
        fi
    else
        issues+=("UNPARSEABLE FILENAME: does not match YYYY-MM-DD HH-mm-ss[-SSS].ext")
        ((unparseable_name_count++))

        if [ -z "$effective_datetime" ]; then
            issues+=("NO EXIF DATE: no DateTimeOriginal or CreateDate found")
            ((no_exif_date_count++))
        fi
    fi

    # --- Report issues for this file ---
    if [ ${#issues[@]} -gt 0 ]; then
        ((files_with_issues++))
        echo "ISSUE: $filename"
        for issue in "${issues[@]}"; do
            echo "  -> $issue"
        done
    fi
done

shopt -u nullglob nocaseglob

# 6. Print summary
echo "--------------------------------------------------------"
echo "Audit Summary"
echo "  Total files scanned:    $total_files"
echo "  Files with issues:      $files_with_issues"
echo "  Files OK:               $((total_files - files_with_issues))"
echo "  ---"
echo "  Timezone mismatches:    $tz_mismatch_count"
echo "  Missing timezone:       $missing_tz_count"
echo "  Datetime mismatches:    $datetime_mismatch_count"
echo "  Subsecond mismatches:   $subsec_mismatch_count"
echo "  No EXIF date:           $no_exif_date_count"
echo "  Unparseable filenames:  $unparseable_name_count"
echo "--------------------------------------------------------"
echo "Audit finished."

if [ "$files_with_issues" -gt 0 ]; then
    exit 1
fi
exit 0
