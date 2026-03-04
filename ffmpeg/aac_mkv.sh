#!/usr/bin/env bash

af=""
if [ "$1" = "dts" ]; then
  af="-af aresample=async=1"
  shift
fi

outdir=""
args=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--out" ]; then
    outdir="$2"
    shift 2
  else
    args+=("$1")
    shift
  fi
done

shopt -s nullglob
for file in *.mkv; do
  base="${file%.mkv}"

  if [ "${#args[@]}" -eq 0 ]; then
    # Auto-detect mode
    ro_srt=""
    en_srt=""
    any_srt=""

    if [ -f "${base}.ro.srt" ]; then
      ro_srt="${base}.ro.srt"
    fi
    if [ -f "${base}.en.srt" ]; then
      en_srt="${base}.en.srt"
    fi
    if [ -z "$ro_srt" ]; then
      for srt in "${base}".*.srt "${base}.srt"; do
        if [ -f "$srt" ]; then
          any_srt="$srt"
          break
        fi
      done
    fi

    if [ -n "$ro_srt" ] && [ -n "$en_srt" ]; then
      # Mode 1.2: two external subtitles
      dest="${outdir:-..}/${file}"
      ffmpeg -i "$file" -i "$ro_srt" -i "$en_srt" \
        -map 0:v:0 -map 0:a:0 -map 1:0 -map 2:0 \
        -metadata:s:s:0 language=ron -metadata:s:s:1 language=eng \
        -disposition:s:0 default \
        -c copy -c:a libfdk_aac $af -vbr 4 \
        -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
        -max_interleave_delta 0 "$dest"

    elif [ -n "$ro_srt" ] || [ -n "$any_srt" ]; then
      # Mode 1.1: one external subtitle (Romanian) + first internal subtitle
      sub="${ro_srt:-$any_srt}"
      dest="${outdir:-..}/${file}"
      ffmpeg -i "$file" -i "$sub" \
        -map 0:v:0 -map 0:a:0 -map 1:0 -map 0:s:0 \
        -metadata:s:s:0 language=ron \
        -disposition:s:0 default \
        -c copy -c:a libfdk_aac $af -vbr 4 \
        -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
        -max_interleave_delta 0 "$dest"

    else
      echo "No subtitle found for $file, skipping"
    fi

  else
    # Mode 2: explicit stream indices
    sub=""
    for srt in "${base}".*.srt "${base}.srt"; do
      if [ -f "$srt" ]; then
        sub="$srt"
        break
      fi
    done

    inputs="-i \"$file\""
    maps="-map 0:v:0"
    submeta=""

    if [ -n "$sub" ]; then
      inputs="$inputs -i \"$sub\""
      maps="$maps -map 1:0"
      submeta="-metadata:s:s:0 language=ron -disposition:s:0 default"
    fi

    for idx in "${args[@]}"; do
      maps="$maps -map 0:$idx"
    done

    dest="${outdir:-..}/${file}"
    eval ffmpeg $inputs $maps $submeta \
      -c copy -c:a libfdk_aac $af -vbr 4 \
      -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
      -max_interleave_delta 0 "\"$dest\""
  fi
done
