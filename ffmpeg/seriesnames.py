#!/usr/bin/env python3
import os
import re
import sys

if len(sys.argv) > 1 and sys.argv[1] in ('-help', '-h'):
    print("""\
Usage: seriesnames.py [v|s]

Rename .mkv and matching .srt files in the current directory based on SxxExx patterns.

Modes:
  (none)  Rename both video and subtitle to SxxExx.mkv / SxxExx.ro.srt
  v       Keep video filename, rename subtitle to <video_base>.ro.srt
  s       Rename video to <subtitle_base>.mkv, subtitle to <subtitle_base>.ro.srt

Matches .mkv files containing SxxExx patterns to .srt files with the same episode.""")
    sys.exit(0)

mode = sys.argv[1] if len(sys.argv) > 1 else None

for filename in os.listdir("."):
    if not filename.endswith(".mkv"):
        continue
    m = re.search(r'[sS](\d{1,2})[eE](\d{1,2})', filename)
    if not m:
        print("No SxxExx pattern found in %s" % filename)
        continue
    tag = "S%02dE%02d" % (int(m.group(1)), int(m.group(2)))
    base = os.path.splitext(filename)[0]

    # find matching subtitle
    srt_match = None
    for srt in os.listdir("."):
        if not srt.endswith(".srt"):
            continue
        if re.search(r'[sS]0?%d[eE]0?%d' % (int(m.group(1)), int(m.group(2))), srt):
            srt_match = srt
            break

    if not srt_match:
        print("%s has no srt match" % filename)
        continue

    srt_base = os.path.splitext(srt_match)[0]
    # strip trailing .ro or .RO if present
    srt_base = re.sub(r'\.ro$', '', srt_base, flags=re.IGNORECASE)

    if mode == 'v':
        # subtitle takes video filename
        new_video = filename
        new_srt = base + ".ro.srt"
    elif mode == 's':
        # video takes subtitle filename (minus .ro)
        new_video = srt_base + ".mkv"
        new_srt = srt_base + ".ro.srt"
    else:
        # default: both renamed to SxxExx pattern
        new_video = tag + ".mkv"
        new_srt = tag + ".ro.srt"

    if filename != new_video:
        os.rename(filename, new_video)
        print("%s -> %s" % (filename, new_video))
    if srt_match != new_srt:
        os.rename(srt_match, new_srt)
        print("%s -> %s" % (srt_match, new_srt))
