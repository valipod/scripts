#!/usr/bin/env bash
if [ $# -eq 0 ]
  then
    echo "No arguments supplied"
fi
shopt -s nullglob
for file in *.mkv
do
  if [ -z "$1" ];
    then
	  #read -t 5 -p "No arguments supplied (proceed in 5 seconds or ENTER) ..."
      ffmpeg -i "$file" -map 0:v:0 -map 0:a:0 -map 0:s:0 -map 0:s:1 -c copy -metadata title= -metadata:s:v title= -metadata:s:a:0 title= -max_interleave_delta 0 "../${file}"
  elif [ -z "$2" ];
    then
    #read -t 5 -p "Target will be saved in $1 (proceed in 5 seconds or ENTER) ..."
    ffmpeg -i "$file" -map 0:v:0 -map 0:a:0 -map 0:s:0 -map 0:s:1 -c copy -metadata title= -metadata:s:v title= -metadata:s:a:0 title= -max_interleave_delta 0 "$1/${file}"
  else
    #read -t 5 -p "Target will be saved in $1/$2 (proceed in 5 seconds or ENTER) ..."
    ffmpeg -i "$file" -map 0:v:0 -map 0:a:0 -map 0:s:0 -map 0:s:1 -c copy -metadata title= -metadata:s:v title= -metadata:s:a:0 title= -max_interleave_delta 0 "$1/$2"
  fi
done
