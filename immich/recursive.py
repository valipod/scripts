#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

if len(sys.argv) > 1 and sys.argv[1] in ('-help', '-h'):
    print("""\
Usage: recursive.py <script_name> [script_parameters...]

Recursively execute a script in the current directory and all subdirectories.

Examples:
  recursive.py filename2tag.py 3          # Write tags if missing, timezone +03:00
  recursive.py filename2tag.py -f 3       # Force overwrite, timezone +03:00
  recursive.py xmp2exif.py                # Sync XMP data to EXIF""")
    sys.exit(0)

if len(sys.argv) < 2:
    print("Usage: recursive.py <script_name> [script_parameters...]", file=sys.stderr)
    sys.exit(1)

script_name = sys.argv[1]
script_params = sys.argv[2:]

found = shutil.which(script_name)
if not found:
    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), script_name)
    if os.path.isfile(script_path):
        found = script_path
    else:
        print(f"Error: Script '{sys.argv[1]}' not found in PATH or script directory.",
              file=sys.stderr)
        sys.exit(1)
script_name = os.path.realpath(found)

root_dir = os.getcwd()

print("Starting recursive processing...")
print(f"Script: {script_name}")
print(f"Parameters: {' '.join(script_params)}")
print(f"Starting from: {root_dir}")
print("---")

dirs = [root_dir]
for dirpath, dirnames, _ in os.walk(root_dir):
    for d in sorted(dirnames):
        dirs.append(os.path.join(dirpath, d))

for d in dirs:
    print(f"-> Processing: {d}")
    result = subprocess.run([sys.executable, script_name] + script_params, cwd=d)
    if result.returncode != 0:
        print(f"Warning: Script failed in {d}. (Exit code: {result.returncode})")
    print("---")

print("Processing complete.")
