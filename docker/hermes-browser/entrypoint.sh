#!/bin/sh
set -eu

mkdir -p /data

if ! touch /data/.hermes-browser-write-test 2>/dev/null; then
  echo "The Chromium profile bind mount at /data must be writable by hermes-browser without disabling the sandbox." >&2
  exit 1
fi

rm -f /data/.hermes-browser-write-test
rm -f /data/SingletonLock /data/SingletonSocket /data/SingletonCookie

exec /usr/bin/chromium \
  --headless=new \
  --disable-gpu \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9222 \
  --user-data-dir=/data \
  about:blank
