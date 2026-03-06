#!/usr/bin/env python3
import os
import re
import shlex
import subprocess
import sys

HELP = """\
Usage: ff.py INPUT [INPUT...] [OPTIONS] OUTPUT

Positional arguments:
  INPUT                Input files (first N-1 bare arguments)
  OUTPUT               Output file (last bare argument)

Stream mapping:
  -v STREAM            Video stream map (default: 0:v:0)
  -a1..a4 STREAM       Audio stream maps (default: 0:a)
  -s1..s7 STREAM       Subtitle stream maps (default: 0:s:0)

Codecs:
  -cv CODEC            Video codec (-c:v)
  -cvc VALUE           Video CRF value
  -ca1..ca4 CODEC      Audio codec (aac|ac3|mp3 have presets, or pass raw)
  -ca1c..ca4c VALUE    Audio quality override (-q)
  -cs1..cs7 CODEC      Subtitle codec (-c:s:N, overrides copy for that stream)

Languages:
  -lv1 LANG            Video language metadata
  -la1..la3 LANG       Audio language metadata
  -ls1..ls7 LANG       Subtitle language metadata

Dispositions:
  -da1..da3 VALUE      Audio disposition (default: a:0=default)
  -ds1..ds3 VALUE      Subtitle disposition (default: s:0=default)

Titles:
  -ta2..ta3 TITLE      Audio stream title
  -ts1..ts7 TITLE      Subtitle stream title

Other:
  -ac VALUE            Audio channels (-ac)
  -af                  Add async audio resampling
  -dts                 Alias for -af (async resampling for DTS sources)

Example:
  ff.py movie.mkv movie.ro.srt movie.en.srt -ca1 aac somepath/movie.mkv"""

AUDIO_PRESETS = {
    'aac': ('libfdk_aac', ['-vbr', '4']),
    'ac3': ('ac3', ['-b:a', '640k']),
    'mp3': ('libmp3lame', ['-q', '2']),
}

LANG_PATTERNS = [
    (r'\.ro\.|\.rum\.|\.rou\.|\.rom\.|\.ron\.', 'ron'),
    (r'\.en\.|\.eng\.', 'eng'),
    (r'\.fr\.|\.fre\.|\.fra\.', 'fre'),
    (r'\.de\.|\.ger\.|\.deu\.', 'ger'),
    (r'\.es\.|\.spa\.', 'spa'),
    (r'\.it\.|\.ita\.', 'ita'),
    (r'\.pt\.|\.por\.', 'por'),
]


def detect_lang(filename):
    fn = filename.lower()
    for pattern, lang in LANG_PATTERNS:
        if re.search(pattern, fn):
            return lang
    return None


def parse_args(argv):
    opts = {}
    positional = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ('-help', '-h'):
            print(HELP)
            sys.exit(0)
        if arg == '--':
            positional.extend(argv[i + 1:])
            break
        if arg in ('-af', '-dts'):
            opts['af'] = ['-filter:a:0', 'aresample=async=1']
            i += 1
            continue
        if arg.startswith('-'):
            key = arg[1:]
            if i + 1 >= len(argv):
                print(f"Option {arg} requires a value", file=sys.stderr)
                sys.exit(1)
            val = argv[i + 1]
            opts[key] = val
            i += 2
            continue
        positional.append(arg)
        i += 1
    return opts, positional


def build_cmd(opts, positional):
    if len(positional) < 2:
        print("Need at least one input and one output", file=sys.stderr)
        sys.exit(1)

    target = positional[-1]
    input_files = positional[:-1]

    cmd = ['ffmpeg']
    for f in input_files:
        cmd += ['-i', f]

    # Stream maps
    v = opts.get('v', '0:v:0')
    cmd += ['-map', v]

    a1 = opts.get('a1', '0:a')
    cmd += ['-map', a1]
    for n in range(2, 5):
        key = f'a{n}'
        if key in opts:
            cmd += ['-map', opts[key], f'-disposition:a:{n - 1}', '0']

    s1 = opts.get('s1', '0:s:0')
    cmd += ['-map', s1]
    for n in range(2, 8):
        key = f's{n}'
        if key in opts:
            cmd += ['-map', opts[key], f'-disposition:s:{n - 1}', '0']

    # Base codec
    cmd += ['-c', 'copy']

    # Video codec
    if 'cv' in opts:
        cmd += ['-c:v', opts['cv']]
    if 'cvc' in opts:
        cmd += ['-crf', opts['cvc']]

    # Audio codecs
    for n in range(1, 5):
        ca_key = f'ca{n}'
        cac_key = f'ca{n}c'
        if ca_key in opts:
            preset = AUDIO_PRESETS.get(opts[ca_key])
            if preset:
                codec, extra = preset
                cmd += [f'-c:a:{n - 1}', codec] + extra
            else:
                cmd += [f'-c:a:{n - 1}', opts[ca_key]]
        if cac_key in opts:
            cmd += ['-q', opts[cac_key]]

    # Audio channels
    if 'ac' in opts:
        cmd += ['-ac', opts['ac']]

    # Subtitle codecs
    for n in range(1, 8):
        cs_key = f'cs{n}'
        if cs_key in opts:
            cmd += [f'-c:s:{n - 1}', opts[cs_key]]

    # Languages
    if 'lv1' in opts:
        cmd += ['-metadata:s:v:0', f"language={opts['lv1']}"]
    for n in range(1, 4):
        la_key = f'la{n}'
        if la_key in opts:
            cmd += [f'-metadata:s:a:{n - 1}', f"language={opts[la_key]}"]

    # Subtitle languages (explicit)
    ls_set = set()
    for n in range(1, 8):
        ls_key = f'ls{n}'
        if ls_key in opts:
            cmd += [f'-metadata:s:s:{n - 1}', f"language={opts[ls_key]}"]
            ls_set.add(n)

    # Auto-detect subtitle language from input filenames
    s_maps = {'s1': s1}
    for n in range(2, 8):
        key = f's{n}'
        if key in opts:
            s_maps[key] = opts[key]
    for key, map_val in s_maps.items():
        n = int(key[1:])
        if n in ls_set:
            continue
        m = re.match(r'(\d+):', map_val)
        if not m:
            continue
        idx = int(m.group(1))
        if idx < len(input_files):
            lang = detect_lang(input_files[idx])
            if lang:
                cmd += [f'-metadata:s:s:{n - 1}', f'language={lang}']

    # Dispositions
    da1 = opts.get('da1', 'default')
    cmd += ['-disposition:a:0', da1]
    for n in range(2, 4):
        da_key = f'da{n}'
        if da_key in opts:
            cmd += [f'-disposition:a:{n - 1}', opts[da_key]]

    ds1 = opts.get('ds1', 'default')
    cmd += ['-disposition:s:0', ds1]
    for n in range(2, 4):
        ds_key = f'ds{n}'
        if ds_key in opts:
            cmd += [f'-disposition:s:{n - 1}', opts[ds_key]]

    # Clear metadata
    cmd += ['-metadata', 'title=', '-metadata:s:v', 'title=',
            '-metadata:s:a:0', 'title=']

    # Titles
    for n in range(2, 4):
        ta_key = f'ta{n}'
        if ta_key in opts:
            cmd += [f'-metadata:s:a:{n - 1}', f"title={opts[ta_key]}"]
    for n in range(1, 8):
        ts_key = f'ts{n}'
        if ts_key in opts:
            cmd += [f'-metadata:s:s:{n - 1}', f"title={opts[ts_key]}"]

    cmd += ['-max_interleave_delta', '0']

    # Audio filter
    if 'af' in opts:
        cmd += opts['af']

    cmd.append(target)
    return cmd


def main():
    opts, positional = parse_args(sys.argv[1:])
    cmd = build_cmd(opts, positional)

    print(shlex.join(cmd))
    input("Press enter to continue")
    sys.exit(subprocess.call(cmd))


if __name__ == '__main__':
    main()
