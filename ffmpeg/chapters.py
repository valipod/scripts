#!/usr/bin/python3
import sys

if len(sys.argv) > 1 and sys.argv[1] in ('-help', '-h'):
    print("""\
Usage: chapters.py

Convert OGM-style chapter markers to ffmpeg metadata format.

Reads:   chapters.txt        (OGM format: CHAPTER01=HH:MM:SS.mmm / CHAPTER01NAME=...)
Writes:  chapters.ffmpeg.txt (ffmpeg metadata with [CHAPTER] sections)

The output file can be used with ffmpeg:
  ffmpeg -i input.mkv -i chapters.ffmpeg.txt -map_metadata 1 -c copy output.mkv""")
    sys.exit(0)

import re

chapters = list()
chap = {}

with open('chapters.txt', 'r') as f:
    for line in f:
        line = line.replace('\ufeff', '')
        x = re.match(r"(\S{7}\d{2})=(\d{2}):(\d{2}):(\d{2})\.(\d{3})", line)
        if x:
            hrs = int(x.group(2))
            mins = int(x.group(3))
            secs = int(x.group(4))
            milisecs = int(x.group(5))

            minutes = (hrs * 60) + mins
            seconds = secs + (minutes * 60)
            timestamp = (seconds * 1000 + milisecs)
            chap = {}
            chap["startTime"] = timestamp
            continue
        y = re.match(r"CHAPTER\d{2}NAME=([\S\ ]+)", line)
        if y:
            title = y.group(1)
            chap["title"] = title
            chapters.append(chap)

text = """;FFMETADATA1
"""

template = """
[CHAPTER]
TIMEBASE=1/1000
START={start}
END={end}
title={title}
"""

for i in range(len(chapters) - 1):
    chap = chapters[i]
    title = chap['title']
    start = chap['startTime']
    end = chapters[i + 1]['startTime'] - 1
    text += template.format(start=start, end=end, title=title)


with open("chapters.ffmpeg.txt", "w") as myfile:
    myfile.write(text)
