#!/bin/python
import os

episodes = {}
for filename in os.listdir("."):
    if filename.endswith("mkv"):
        number = filename[0:6]
        name = filename [7:-4]
        episodes[number] = name
for filename in os.listdir("."):
    if filename.endswith("srt"):
        number = filename[0:6]
        name = episodes.get(number)
        if name:
            os.rename(filename, "%s %s.ro.srt" % (number, name))
        else:
            print("%s has no mkv match" % number)


