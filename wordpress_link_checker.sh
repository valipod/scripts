#!/bin/bash
# Check links on a WordPress site with LinkChecker in Docker; asks for options.

read -rp "URL [https://florentinatilea.ro]: " URL
URL=${URL:-https://florentinatilea.ro}

read -rp "Show warnings too? [y/N]: " ans
case $ans in [yY]*) ERRORS_ONLY= ;; *) ERRORS_ONLY=--no-warnings ;; esac

read -rp "Output file (empty = terminal): " OUT

run() {
  docker run --rm --network host ghcr.io/linkchecker/linkchecker \
    --check-extern --no-status $ERRORS_ONLY \
    --ignore-url='\?share=' --ignore-url='/xmlrpc\.php' \
    --ignore-url='i\.ytimg\.com' --ignore-url='player\.vimeo\.com' \
    --ignore-url='\?(p|attachment_id)=' \
    "$URL"
}

if [ -n "$OUT" ]; then
  echo "Checking $URL, writing to $OUT ..."
  run > "$OUT" 2>&1
  tail -2 "$OUT"
else
  run
fi

