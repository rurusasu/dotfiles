#!/bin/sh
set -eu

curl -fsS http://127.0.0.1:9222/json/version >/dev/null
curl -fsS http://127.0.0.1:6080/ | grep -q 'noVNC'

python3 - <<'PY'
import socket

with socket.create_connection(("127.0.0.1", 5900), timeout=3):
    pass
PY
