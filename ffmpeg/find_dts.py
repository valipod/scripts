#!/usr/bin/env python3
import json
import os
import subprocess
import sys

if len(sys.argv) > 1 and sys.argv[1] in ('-help', '-h'):
    print("""\
Usage: find_dts.py PATH

Recursively search for .mkv files under PATH and list those containing
DTS audio streams (dts, dts-hd, truehd).

Output: one line per match showing the file path and DTS stream details.""")
    sys.exit(0)

root = sys.argv[1] if len(sys.argv) > 1 else '.'

for dirpath, _dirs, files in os.walk(root):
    for fname in sorted(files):
        if not fname.lower().endswith('.mkv'):
            continue
        fpath = os.path.join(dirpath, fname)
        try:
            result = subprocess.run(
                ['ffprobe', '-v', 'quiet', '-print_format', 'json',
                 '-show_streams', '-select_streams', 'a', fpath],
                capture_output=True, text=True, timeout=30)
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            print(f"ERROR: {fpath}: {e}", file=sys.stderr)
            continue

        if result.returncode != 0:
            continue

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            continue

        dts_streams = []
        for stream in data.get('streams', []):
            codec = stream.get('codec_name', '').lower()
            if codec in ('dts', 'dca'):
                profile = stream.get('profile', '')
                dts_streams.append(profile if profile else 'DTS')
            elif codec == 'truehd':
                dts_streams.append('TrueHD')

        if dts_streams:
            print(f"{fpath}  [{', '.join(dts_streams)}]")
