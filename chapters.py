#!/usr/bin/python3
import re

chapters = list()

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
            chap = {
                "startTime": timestamp
            }
            continue
        y = re.match(r"CHAPTER\d{2}NAME=([\S\ ]+)", line)
        if y:
            # every other line doesn't contain any new information but
            # is formatted differently
            y = re.match(r"CHAPTER\d{2}NAME=([\S\ ]+)", line)
            title = y.group(0)
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
    text += """
[CHAPTER]
TIMEBASE=1/1000
START={start}
END={end}
title={title}
""".format(start=start, end=end, title=title)


with open("chapters.ffmpeg.txt", "a") as myfile:
    myfile.write(text)
