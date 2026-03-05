#!/usr/bin/env python3
import glob
import os
import subprocess
import sys

HELP = """\
Usage: mkv.py [aac|dts|copy] [STREAM_INDICES...] [--out PATH]

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
  mkv.py                          Auto-detect, copy streams, output to ../
  mkv.py aac                      Auto-detect, re-encode audio to AAC
  mkv.py 0 1 2 3                  Explicit streams, copy, output to ../
  mkv.py aac 0 1 --out /dst/      Re-encode audio, explicit streams, output to /dst/
  mkv.py 0 1 --out "/path/to/Movie (2008).mkv"   Explicit output filename"""


def find_srt(base):
    for pattern in [f'{base}.*.srt', f'{base}.srt']:
        matches = glob.glob(pattern)
        for m in matches:
            if os.path.isfile(m):
                return m
    return None


def get_dest(outdir, filename):
    if outdir and outdir.lower().endswith('.mkv'):
        return outdir
    return os.path.join(outdir or '..', filename)


def run_ffmpeg(cmd):
    print(' '.join(cmd))
    return subprocess.call(cmd)


def auto_detect(file, base, codec, af, outdir):
    ro_srt = f'{base}.ro.srt' if os.path.isfile(f'{base}.ro.srt') else None
    en_srt = f'{base}.en.srt' if os.path.isfile(f'{base}.en.srt') else None

    any_srt = None
    if not ro_srt:
        any_srt = find_srt(base)

    dest = get_dest(outdir, file)

    if ro_srt and en_srt:
        cmd = ['ffmpeg', '-i', file, '-i', ro_srt, '-i', en_srt,
               '-map', '0:v:0', '-map', '0:a:0', '-map', '1:0', '-map', '2:0',
               '-metadata:s:s:0', 'language=ron', '-metadata:s:s:1', 'language=eng',
               '-disposition:s:0', 'default']
        cmd += codec + af
        cmd += ['-metadata', 'title=', '-metadata:s:v', 'title=',
                '-metadata:s:a', 'title=', '-metadata:s:s', 'title=',
                '-max_interleave_delta', '0', dest]
        return run_ffmpeg(cmd)

    if ro_srt or any_srt:
        sub = ro_srt or any_srt
        cmd = ['ffmpeg', '-i', file, '-i', sub,
               '-map', '0:v:0', '-map', '0:a:0', '-map', '1:0', '-map', '0:s:0',
               '-metadata:s:s:0', 'language=ron',
               '-disposition:s:0', 'default']
        cmd += codec + af
        cmd += ['-metadata', 'title=', '-metadata:s:v', 'title=',
                '-metadata:s:a', 'title=', '-metadata:s:s', 'title=',
                '-max_interleave_delta', '0', dest]
        return run_ffmpeg(cmd)

    print(f'No subtitle found for {file}, skipping')
    return 0


def explicit_streams(file, base, args, codec, af, outdir):
    sub = find_srt(base)
    dest = get_dest(outdir, file)

    cmd = ['ffmpeg', '-i', file]
    maps = ['-map', '0:v:0']

    if sub:
        cmd += ['-i', sub]
        maps += ['-map', '1:0']

    for idx in args:
        maps += ['-map', f'0:{idx}']

    cmd += maps
    if sub:
        cmd += ['-metadata:s:s:0', 'language=ron', '-disposition:s:0', 'default']
    cmd += codec + af
    cmd += ['-metadata', 'title=', '-metadata:s:v', 'title=',
            '-metadata:s:a', 'title=', '-metadata:s:s', 'title=',
            '-max_interleave_delta', '0', dest]
    return run_ffmpeg(cmd)


def main():
    argv = sys.argv[1:]

    if argv and argv[0] in ('--help', '-h'):
        print(HELP)
        sys.exit(0)

    # Parse codec mode
    codec = ['-c', 'copy']
    af = []
    if argv and argv[0] in ('aac', 'dts', 'copy'):
        mode = argv.pop(0)
        if mode == 'aac':
            codec = ['-c', 'copy', '-c:a', 'libfdk_aac', '-vbr', '4']
        elif mode == 'dts':
            codec = ['-c', 'copy', '-c:a', 'libfdk_aac', '-vbr', '4']
            af = ['-filter:a:0', 'aresample=async=1']

    # Parse --out and stream indices
    outdir = None
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == '--out':
            outdir = argv[i + 1]
            i += 2
        else:
            args.append(argv[i])
            i += 1

    mkv_files = sorted(glob.glob('*.mkv'))
    if not mkv_files:
        print('No .mkv files found in current directory')
        sys.exit(1)

    for file in mkv_files:
        base = file[:-4]  # strip .mkv
        if not args:
            auto_detect(file, base, codec, af, outdir)
        else:
            explicit_streams(file, base, args, codec, af, outdir)


if __name__ == '__main__':
    main()
