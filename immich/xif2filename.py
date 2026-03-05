#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys

HELP = """\
Usage: xif2filename.py <timezone_offset> [file]

Read EXIF date/time from media files and rename them to standardized format:
  YYYY-MM-DD HH-mm-ss[-SSS].ext

Only includes milliseconds if the EXIF subsecond value is non-zero.
Also updates EXIF tags with the normalized timezone offset.

Examples:
  xif2filename.py 3               # All files in current folder
  xif2filename.py -5              # All files, timezone -05:00
  xif2filename.py +02:00 image.jpg  # Single file"""

IMAGE_EXTS = ('jpg', 'jpeg', 'png', 'heic')
VIDEO_EXTS = ('mp4', 'mov')
ALL_EXTS = IMAGE_EXTS + VIDEO_EXTS


def normalize_tz(tz):
    m = re.match(r'^([+-]?)(\d{1,2})$', tz)
    if m:
        sign = m.group(1) or '+'
        return f'{sign}{int(m.group(2)):02d}:00'
    m = re.match(r'^([+-])(\d{1,2}):(\d{2})$', tz)
    if m:
        return f'{m.group(1)}{int(m.group(2)):02d}:{m.group(3)}'
    print(f"Error: Invalid timezone offset format: {tz}", file=sys.stderr)
    sys.exit(1)


def run_exiftool(args):
    return subprocess.run(['exiftool'] + args, capture_output=True, text=True)


def parse_exif_output(output):
    tags = {}
    for line in output.strip().splitlines():
        parts = line.split(':', 1)
        if len(parts) == 2:
            tags[parts[0].strip()] = parts[1].strip()
    return tags


def collect_files():
    files = []
    for ext in ALL_EXTS:
        files.extend(glob.glob(f'*.{ext}'))
        files.extend(glob.glob(f'*.{ext.upper()}'))
    return sorted(set(files))


def main():
    argv = list(sys.argv[1:])

    if argv and argv[0] in ('--help', '-h'):
        print(HELP)
        sys.exit(0)

    if not argv:
        print("Error: Missing timezone offset parameter.", file=sys.stderr)
        sys.exit(1)

    tz = normalize_tz(argv[0])
    single_file = argv[1] if len(argv) > 1 else None

    print(f"Timezone offset: {tz}")

    if not single_file and os.path.isfile('.filename'):
        print(f"Skipping: .filename file exists in {os.getcwd()} (already processed)")
        sys.exit(0)

    print("EXIF to Filename Rename Started...")
    print("--------------------------------------------------------")

    file_list = [single_file] if single_file else collect_files()

    for file in file_list:
        if not os.path.isfile(file):
            continue

        filename = os.path.basename(file)
        extension = filename.rsplit('.', 1)[-1] if '.' in filename else ''

        print(f"Processing: {filename}")

        result = run_exiftool(['-s', '-s',
                               '-FileTypeExtension', '-DateTimeOriginal', '-CreateDate',
                               '-SubSecTimeOriginal', '-SubSecTimeDigitized',
                               file])
        tags = parse_exif_output(result.stdout)

        actual_ext = tags.get('FileTypeExtension', '')
        datetime_val = tags.get('DateTimeOriginal', '')
        subsec = tags.get('SubSecTimeOriginal', '')

        if not datetime_val:
            datetime_val = tags.get('CreateDate', '')
            subsec = tags.get('SubSecTimeDigitized', '')

        orig_subsec = subsec

        if actual_ext and actual_ext.lower() != extension.lower():
            print(f"  -> INFO: Extension mismatch — file is {actual_ext.upper()} "
                  f"but named .{extension}. Using .{actual_ext.lower()}.")
            extension = actual_ext

        if not datetime_val:
            print("  -> INFO: No DateTimeOriginal or CreateDate found. Skipping.")
            continue

        has_subsec = bool(subsec) and subsec not in ('0', '00', '000')

        if has_subsec:
            subsec_filename = (subsec[:3]).ljust(3, '0')
            if len(orig_subsec) == 6 and orig_subsec[:3] == '000':
                subsec_exif = orig_subsec[3:6] + '000'
            else:
                subsec_exif = orig_subsec.ljust(6, '0')[:6]

        m = re.match(r'(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})', datetime_val)
        if not m:
            print(f"  -> WARNING: Could not parse datetime format: {datetime_val}")
            continue

        year, month, day, hour, minute, second = m.groups()

        if has_subsec:
            new_filename = f"{year}-{month}-{day} {hour}-{minute}-{second}-{subsec_filename}.{extension.lower()}"
        else:
            new_filename = f"{year}-{month}-{day} {hour}-{minute}-{second}.{extension.lower()}"

        target_file = filename
        renamed = False

        if filename != new_filename:
            if os.path.isfile(new_filename):
                print(f"  -> WARNING: Target file {new_filename} already exists. "
                      "Skipping rename, still updating EXIF.")
            else:
                print(f"  -> Renaming to: {new_filename}")
                try:
                    os.rename(file, new_filename)
                    print(f"  -> Renamed {filename} -> {new_filename}")
                    xmp_file = f"{file}.xmp"
                    if os.path.isfile(xmp_file):
                        new_xmp = f"{new_filename}.xmp"
                        os.rename(xmp_file, new_xmp)
                        print(f"  -> Renamed XMP sidecar: {filename}.xmp -> {new_filename}.xmp")
                    target_file = new_filename
                    renamed = True
                except OSError as e:
                    print(f"  -> ERROR: Failed to rename {filename}: {e}")
                    continue
        else:
            print("  -> INFO: Already named correctly. Updating EXIF.")

        new_datetime = f"{year}:{month}:{day} {hour}:{minute}:{second}{tz}"
        exif_args = ['-q', '-m', '-P', '-overwrite_original',
                     f'-DateTimeOriginal={new_datetime}',
                     f'-CreateDate={new_datetime}',
                     f'-ModifyDate={new_datetime}',
                     f'-OffsetTime={tz}',
                     f'-OffsetTimeOriginal={tz}',
                     f'-OffsetTimeDigitized={tz}']

        if has_subsec:
            exif_args += [f'-SubSecTimeOriginal={subsec_exif}',
                          f'-SubSecTimeDigitized={subsec_exif}',
                          f'-SubSecTime={subsec_exif}']

        result = subprocess.run(['exiftool'] + exif_args + [target_file])
        if result.returncode == 0:
            if has_subsec:
                print(f"  -> SUCCESS: Updated EXIF with timezone {tz} and subsecond {subsec_exif}")
            else:
                print(f"  -> SUCCESS: Updated EXIF with timezone {tz} (no subsecond)")
        else:
            label = "Renamed but failed" if renamed else "Failed"
            print(f"  -> WARNING: {label} to update EXIF timezone/subsecond")

    if not single_file:
        open('.filename', 'w').close()
        print(f"Created .filename marker file in {os.getcwd()}")

    print("--------------------------------------------------------")
    print("Script finished.")


if __name__ == '__main__':
    main()
