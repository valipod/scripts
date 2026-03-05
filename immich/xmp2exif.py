#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys

HELP = """\
Usage: xmp2exif.py [file]

Sync XMP sidecar data into the corresponding image/video EXIF tags.
Extracts GPS coordinates and DateTimeOriginal from .xmp files.

Examples:
  xmp2exif.py              # Process all XMP sidecars in current folder
  xmp2exif.py image.jpg    # Process only image.jpg.xmp"""


def dms_to_decimal(dms):
    """Convert degrees-minutes-direction to signed decimal degrees.
    Input: '20 34.668N' -> 20.5778000
    """
    direction = dms[-1]
    numeric = dms[:-1].strip()
    parts = numeric.split()
    degrees = float(parts[0])
    minutes = float(parts[1]) if len(parts) > 1 else 0.0
    decimal = degrees + minutes / 60.0
    if direction in ('S', 'W'):
        decimal = -decimal
    return decimal


def main():
    argv = list(sys.argv[1:])

    if argv and argv[0] in ('--help', '-h'):
        print(HELP)
        sys.exit(0)

    single_file = argv[0] if argv else None

    print("XMP Sidecar to EXIF Sync Started...")
    print("--------------------------------------------------------")

    if single_file:
        base = single_file.removesuffix('.xmp')
        xmp_files = [f"{base}.xmp"] if os.path.isfile(f"{base}.xmp") else []
    else:
        xmp_files = sorted(glob.glob('*.xmp') + glob.glob('*.XMP'))

    for xmp_file in xmp_files:
        image_file = xmp_file.removesuffix('.xmp').removesuffix('.XMP')
        if xmp_file.endswith('.XMP'):
            image_file = xmp_file[:-4]
        else:
            image_file = xmp_file[:-4]

        xmp_name = os.path.basename(xmp_file)
        image_name = os.path.basename(image_file)

        print(f"Processing XMP: {xmp_name}")

        if not os.path.isfile(image_file):
            print(f"  -> WARNING: Image file {image_name} not found. Skipping {xmp_name}.")
            continue

        with open(xmp_file, 'r', errors='replace') as f:
            xmp_content = f.read()

        raw_lat = None
        raw_lon = None
        raw_datetime = None

        m = re.search(r'<exif:GPSLatitude>([^<]+)', xmp_content)
        if m:
            raw_lat = m.group(1)
        m = re.search(r'<exif:GPSLongitude>([^<]+)', xmp_content)
        if m:
            raw_lon = m.group(1)
        m = re.search(r'<exif:DateTimeOriginal>([^<]+)', xmp_content)
        if m:
            raw_datetime = m.group(1)

        ext = image_name.rsplit('.', 1)[-1].lower() if '.' in image_name else ''
        is_video = ext in ('mp4', 'mov')

        exif_args = ['-q', '-m', '-P', '-overwrite_original']
        gps_updated = False
        date_updated = False

        if raw_lat and raw_lon:
            lat_formatted = raw_lat.replace(',', ' ')
            lon_formatted = raw_lon.replace(',', ' ')
            lat_ref = lat_formatted[-1]
            lon_ref = lon_formatted[-1]

            print(f"  -> XMP Coords: Lat {lat_formatted}, Lon {lon_formatted}")

            if is_video:
                lat_dec = dms_to_decimal(lat_formatted)
                lon_dec = dms_to_decimal(lon_formatted)
                gps_iso = f"{lat_dec:+.7f}{lon_dec:+.7f}/"
                exif_args.append(f'-UserData:GPSCoordinates={gps_iso}')
            else:
                exif_args += [
                    f'-GPSLatitude={lat_formatted}',
                    f'-GPSLatitudeRef={lat_ref}',
                    f'-GPSLongitude={lon_formatted}',
                    f'-GPSLongitudeRef={lon_ref}',
                ]
            gps_updated = True
        else:
            print(f"  -> INFO: GPS coordinates not found in {xmp_name}.")

        if raw_datetime:
            print(f"  -> XMP Date: {raw_datetime}")
            exif_args += [
                f'-DateTimeOriginal={raw_datetime}',
                f'-CreateDate={raw_datetime}',
                f'-ModifyDate={raw_datetime}',
            ]

            subsec_m = re.search(r'\.(\d{1,3})', raw_datetime)
            if subsec_m:
                subsec = subsec_m.group(1)
                print(f"  -> XMP SubSec: {subsec}")
                exif_args += [
                    f'-SubSecTimeOriginal={subsec}',
                    f'-SubSecTimeDigitized={subsec}',
                    f'-SubSecTime={subsec}',
                ]

            tz_m = re.search(r'([+-]\d{2}:\d{2})$', raw_datetime)
            if tz_m:
                tz_offset = tz_m.group(1)
                print(f"  -> XMP Timezone: {tz_offset}")
                exif_args += [
                    f'-OffsetTime={tz_offset}',
                    f'-OffsetTimeOriginal={tz_offset}',
                    f'-OffsetTimeDigitized={tz_offset}',
                ]
            date_updated = True
        else:
            print(f"  -> INFO: DateTimeOriginal not found in {xmp_name}.")

        if not gps_updated and not date_updated:
            print(f"  -> INFO: No GPS or DateTimeOriginal found. Skipping {xmp_name}.")
            print("---")
            continue

        result = subprocess.run(['exiftool'] + exif_args + [image_file])
        if result.returncode == 0:
            print(f"  -> SUCCESS: Baked data into {image_name}.")
        else:
            print(f"  -> ERROR: ExifTool failed to update {image_name}.")

        print("---")

    print("--------------------------------------------------------")
    print("Script finished.")


if __name__ == '__main__':
    main()
