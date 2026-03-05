#!/usr/bin/env bash

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  cat <<'EOF'
Usage: mkv.sh [aac|dts|copy] [STREAM_INDICES...] [--out PATH]

Remux all .mkv files in the current directory, merging external .srt subtitles.

Codec modes (first argument, optional):
  aac   Re-encode audio to AAC (libfdk_aac VBR 4)
  dts   Same as aac, with async resampling (for DTS sources)
  copy  Copy all streams as-is (default if omitted)

Stream selection:
  If no stream indices are given, auto-detect mode is used:
    - Looks for <name>.ro.srt and <name>.en.srt for external subtitles
    - Falls back to any .srt file found
    - Maps video, audio, and discovered subtitles automatically

  If stream indices are given (e.g. 0 1 2 3), explicit mode is used:
    - Maps video stream 0 plus the specified streams from the source
    - Also merges an external .srt if one exists

Output (--out PATH):
  --out dir/          Write output to dir/<original_filename>.mkv
  --out file.mkv      Write output to that exact file path
  (default)           Write to ../<original_filename>.mkv

Examples:
  mkv.sh                          Auto-detect, copy streams, output to ../
  mkv.sh aac                      Auto-detect, re-encode audio to AAC
  mkv.sh 0 1 2 3                  Explicit streams, copy, output to ../
  mkv.sh aac 0 1 --out /dst/      Re-encode audio, explicit streams, output to /dst/
  mkv.sh 0 1 --out "/path/to/Movie (2008).mkv"   Explicit output filename
EOF
  exit 0
fi

codec="-c copy"
af=""
case "$1" in
  aac) codec="-c copy -c:a libfdk_aac -vbr 4"; shift ;;
  dts) codec="-c copy -c:a libfdk_aac -vbr 4"; af="-filter:a:0 aresample=async=1"; shift ;;
  copy) shift ;;
esac

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
      # Two external subtitles
      if [ -n "$outdir" ] && [[ "$outdir" == *.mkv ]]; then
        dest="$outdir"
      else
        dest="${outdir:-..}/${file}"
      fi
      ffmpeg -i "$file" -i "$ro_srt" -i "$en_srt" \
        -map 0:v:0 -map 0:a:0 -map 1:0 -map 2:0 \
        -metadata:s:s:0 language=ron -metadata:s:s:1 language=eng \
        -disposition:s:0 default \
        $codec $af \
        -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
        -max_interleave_delta 0 "$dest"

    elif [ -n "$ro_srt" ] || [ -n "$any_srt" ]; then
      # One external subtitle (Romanian) + first internal subtitle
      sub="${ro_srt:-$any_srt}"
      if [ -n "$outdir" ] && [[ "$outdir" == *.mkv ]]; then
        dest="$outdir"
      else
        dest="${outdir:-..}/${file}"
      fi
      ffmpeg -i "$file" -i "$sub" \
        -map 0:v:0 -map 0:a:0 -map 1:0 -map 0:s:0 \
        -metadata:s:s:0 language=ron \
        -disposition:s:0 default \
        $codec $af \
        -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
        -max_interleave_delta 0 "$dest"

    else
      echo "No subtitle found for $file, skipping"
    fi

  else
    # Explicit stream indices
    sub=""
    for srt in "${base}".*.srt "${base}.srt"; do
      if [ -f "$srt" ]; then
        sub="$srt"
        break
      fi
    done

    cmd=(ffmpeg -i "$file")
    mapcmd=(-map 0:v:0)

    if [ -n "$sub" ]; then
      cmd+=(-i "$sub")
      mapcmd+=(-map 1:0)
    fi

    for idx in "${args[@]}"; do
      mapcmd+=(-map "0:$idx")
    done

    if [ -n "$outdir" ] && [[ "$outdir" == *.mkv ]]; then
      dest="$outdir"
    else
      dest="${outdir:-..}/${file}"
    fi
    "${cmd[@]}" "${mapcmd[@]}" \
      ${sub:+-metadata:s:s:0 language=ron -disposition:s:0 default} \
      $codec $af \
      -metadata title= -metadata:s:v title= -metadata:s:a title= -metadata:s:s title= \
      -max_interleave_delta 0 "$dest"
  fi
done
