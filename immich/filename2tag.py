#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys

HELP = """\
Usage: filename2tag.py [-f] <timezone_offset> [file]

Extract date/time from filenames and write to EXIF tags.
By default, only writes tags if missing. Use -f to force overwrite.

Examples:
  filename2tag.py 3                # All files, only write if tag is missing
  filename2tag.py -f +03:00        # All files, force overwrite existing tags
  filename2tag.py -6 image.jpg     # Single file"""

IMAGE_EXTS = ('jpg', 'jpeg', 'png', 'heic')
VIDEO_EXTS = ('mp4', 'mov')
ALL_EXTS = IMAGE_EXTS + VIDEO_EXTS

FILENAME_RE = re.compile(
    r'^(\d{4})-(\d{2})-(\d{2})[ _]+(\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?'
)


def normalize_tz(tz):
    m = re.match(r'^([+-]?)(\d{1,2})$', tz)
    if m:
        sign = m.group(1) or '+'
        return f'{sign}{int(m.group(2)):02d}:00'
    m = re.match(r'^([+-])(\d{1,2}):(\d{2})$', tz)
    if m:
        return f'{m.group(1)}{int(m.group(2)):02d}:{m.group(3)}'
    print(f"Error: Invalid timezone offset format: {tz}", file=sys.stderr)
    print("Please use format like 3, -5, +02:00, or -5:30.", file=sys.stderr)
    sys.exit(1)


def run_exiftool(args, cwd=None):
    return subprocess.run(['exiftool'] + args, cwd=cwd)


def build_exiftool_args(filename, tz, force, is_video):
    m = FILENAME_RE.match(os.path.basename(filename))
    if not m:
        return None
    year, month, day, hour, minute, second = m.group(1, 2, 3, 4, 5, 6)
    subsec = m.group(7)

    datetime_val = f'{year}:{month}:{day} {hour}:{minute}:{second}{tz}'
    subsec_val = subsec if subsec else '000'

    args = ['-n', '-overwrite_original_in_place', '-P']
    if not force:
        if is_video:
            args += ['-if', 'not $createdate']
        else:
            args += ['-if', 'not $datetimeoriginal']

    args += [
        f'-DateTimeOriginal={datetime_val}',
        f'-CreateDate={datetime_val}',
        f'-ModifyDate={datetime_val}',
        f'-SubSecTimeOriginal={subsec_val}',
        f'-SubSecTimeDigitized={subsec_val}',
        f'-SubSecTime={subsec_val}',
        f'-OffsetTime={tz}',
        f'-OffsetTimeOriginal={tz}',
        f'-OffsetTimeDigitized={tz}',
    ]
    return args


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

    force = False
    if argv and argv[0] == '-f':
        force = True
        argv.pop(0)

    if not argv:
        print("Error: Missing timezone offset parameter.", file=sys.stderr)
        sys.exit(1)

    tz = normalize_tz(argv[0])
    single_file = argv[1] if len(argv) > 1 else None

    print(f"Timezone offset: {tz}")
    print(f"Mode: {'Force overwrite' if force else 'Only write if missing'}")

    if not single_file and os.path.isfile('.time'):
        print(f"Skipping: .time file exists in {os.getcwd()} (already processed)")
        sys.exit(0)

    if single_file:
        file_list = [single_file]
    else:
        file_list = collect_files()

    for f in file_list:
        if not os.path.isfile(f):
            continue
        ext = f.rsplit('.', 1)[-1].lower() if '.' in f else ''
        is_video = ext in VIDEO_EXTS

        args = build_exiftool_args(f, tz, force, is_video)
        if args is None:
            continue

        print(f"--- {'Video' if is_video else 'Image'} Processing: {f}")
        run_exiftool(args + [f])

    if not single_file:
        open('.time', 'w').close()
        print(f"Created .time marker file in {os.getcwd()}")


if __name__ == '__main__':
    main()
