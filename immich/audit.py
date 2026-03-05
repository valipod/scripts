#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys

HELP = """\
Usage: audit.py <timezone_offset>

Audit media files by comparing EXIF metadata against expected values.
Checks timezone offset consistency and filename-to-EXIF datetime agreement.
Read-only — no files are modified.

Examples:
  audit.py 3           # Expected timezone +03:00
  audit.py -5          # Expected timezone -05:00
  audit.py +02:00      # Expected timezone +02:00"""

IMAGE_EXTS = ('jpg', 'jpeg', 'png', 'heic')
VIDEO_EXTS = ('mp4', 'mov')
ALL_EXTS = IMAGE_EXTS + VIDEO_EXTS

FILENAME_RE = re.compile(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?[^.]*\.([a-zA-Z0-9]+)$'
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
    sys.exit(1)


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

    if argv and argv[0] in ('-help', '-h'):
        print(HELP)
        sys.exit(0)

    if not argv:
        print("Error: Missing timezone offset parameter.", file=sys.stderr)
        sys.exit(1)

    tz = normalize_tz(argv[0])
    print(f"Expected timezone offset: {tz}")
    print("Audit Started...")
    print("--------------------------------------------------------")

    total_files = 0
    files_with_issues = 0
    tz_mismatch_count = 0
    missing_tz_count = 0
    datetime_mismatch_count = 0
    subsec_mismatch_count = 0
    no_exif_date_count = 0
    unparseable_name_count = 0
    issue_files = []

    for file in collect_files():
        if not os.path.isfile(file):
            continue

        total_files += 1
        filename = os.path.basename(file)
        issues = []

        result = subprocess.run(
            ['exiftool', '-s', '-s',
             '-DateTimeOriginal', '-CreateDate',
             '-SubSecTimeOriginal', '-SubSecTimeDigitized',
             '-OffsetTimeOriginal', file],
            capture_output=True, text=True)
        tags = parse_exif_output(result.stdout)

        exif_datetime = tags.get('DateTimeOriginal', '')
        exif_createdate = tags.get('CreateDate', '')
        exif_subsec = tags.get('SubSecTimeOriginal', '')
        exif_subsec_digitized = tags.get('SubSecTimeDigitized', '')
        exif_tz = tags.get('OffsetTimeOriginal', '')

        effective_datetime = exif_datetime or exif_createdate
        effective_subsec = exif_subsec if exif_datetime else exif_subsec_digitized

        # Check timezone
        if exif_tz:
            if exif_tz != tz:
                issues.append(f"TIMEZONE MISMATCH: OffsetTimeOriginal='{exif_tz}', expected '{tz}'")
                tz_mismatch_count += 1
        elif effective_datetime:
            m = re.search(r'([+-]\d{2}:\d{2})$', effective_datetime)
            if m:
                embedded_tz = m.group(1)
                if embedded_tz != tz:
                    issues.append(f"TIMEZONE MISMATCH: datetime contains '{embedded_tz}', expected '{tz}'")
                    tz_mismatch_count += 1
            else:
                issues.append(f"MISSING TIMEZONE: no OffsetTimeOriginal and no timezone in datetime string (expected {tz})")
                missing_tz_count += 1
        else:
            issues.append(f"MISSING TIMEZONE: no OffsetTimeOriginal and no datetime found (expected {tz})")
            missing_tz_count += 1

        # Parse filename and compare
        fn_match = FILENAME_RE.match(filename)
        if fn_match:
            fn_year, fn_month, fn_day = fn_match.group(1, 2, 3)
            fn_hour, fn_min, fn_sec = fn_match.group(4, 5, 6)
            fn_subsec = fn_match.group(7)
            fn_ext = fn_match.group(8)
            fn_datetime = f"{fn_year}:{fn_month}:{fn_day} {fn_hour}:{fn_min}:{fn_sec}"
            is_video = fn_ext.lower() in VIDEO_EXTS

            if not effective_datetime:
                issues.append("NO EXIF DATE: no DateTimeOriginal or CreateDate found")
                no_exif_date_count += 1
            else:
                exif_datetime_bare = re.sub(r'[+-]\d{2}:\d{2}$', '', effective_datetime)
                if fn_datetime != exif_datetime_bare:
                    issues.append(f"DATETIME MISMATCH: filename='{fn_datetime}', EXIF='{exif_datetime_bare}'")
                    datetime_mismatch_count += 1
                elif fn_subsec and not is_video:
                    normalized_exif_subsec = ''
                    if effective_subsec:
                        normalized_exif_subsec = effective_subsec[:3].ljust(3, '0')
                    if fn_subsec != normalized_exif_subsec:
                        issues.append(f"SUBSEC MISMATCH: filename='{fn_subsec}', EXIF='{effective_subsec}' (normalized: '{normalized_exif_subsec}')")
                        subsec_mismatch_count += 1
        else:
            issues.append("UNPARSEABLE FILENAME: does not match YYYY-MM-DD HH-mm-ss[-SSS].ext")
            unparseable_name_count += 1
            if not effective_datetime:
                issues.append("NO EXIF DATE: no DateTimeOriginal or CreateDate found")
                no_exif_date_count += 1

        if issues:
            files_with_issues += 1
            issue_files.append(filename)
            print(f"ISSUE: {filename}")
            for issue in issues:
                print(f"  -> {issue}")

    print("--------------------------------------------------------")
    print("Audit Summary")
    print(f"  Total files scanned:    {total_files}")
    print(f"  Files with issues:      {files_with_issues}")
    print(f"  Files OK:               {total_files - files_with_issues}")
    print("  ---")
    print(f"  Timezone mismatches:    {tz_mismatch_count}")
    print(f"  Missing timezone:       {missing_tz_count}")
    print(f"  Datetime mismatches:    {datetime_mismatch_count}")
    print(f"  Subsecond mismatches:   {subsec_mismatch_count}")
    print(f"  No EXIF date:           {no_exif_date_count}")
    print(f"  Unparseable filenames:  {unparseable_name_count}")
    print("--------------------------------------------------------")

    if issue_files:
        print()
        print("Files with issues:")
        for f in issue_files:
            print(f)

    print("--------------------------------------------------------")
    print("Audit finished.")
    sys.exit(1 if files_with_issues > 0 else 0)


if __name__ == '__main__':
    main()
