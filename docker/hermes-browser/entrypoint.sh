#!/bin/sh
set -eu

mkdir -p /data

if ! touch /data/.hermes-browser-write-test 2>/dev/null; then
  echo "The Chromium profile bind mount at /data must be writable by hermes-browser without disabling the sandbox." >&2
  exit 1
fi

rm -f /data/.hermes-browser-write-test
rm -f /data/SingletonLock /data/SingletonSocket /data/SingletonCookie

cat >/tmp/hermes-cdp-forwarder.py <<'PY'
import os
import selectors
import socket
import sys

UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 9223
EXTERNAL_PORT = 9222


def read_until_headers(fd):
  chunks = []
  data = b""
  while b"\r\n\r\n" not in data:
    chunk = os.read(fd, 65536)
    if not chunk:
      break
    chunks.append(chunk)
    data = b"".join(chunks)
  return data


def split_headers(data):
  header_end = data.find(b"\r\n\r\n")
  if header_end == -1:
    return data, b""
  return data[:header_end + 4], data[header_end + 4:]


def get_header(headers, name):
  prefix = name.lower().encode("ascii") + b":"
  for line in headers.split(b"\r\n")[1:]:
    if line.lower().startswith(prefix):
      return line.split(b":", 1)[1].strip().decode("ascii", "ignore")
  return ""


def replace_header(headers, name, value):
  lines = headers.split(b"\r\n")
  prefix = name.lower().encode("ascii") + b":"
  replaced = False
  for index, line in enumerate(lines):
    if line.lower().startswith(prefix):
      lines[index] = f"{name}: {value}".encode("ascii")
      replaced = True
  if not replaced:
    lines.insert(-2, f"{name}: {value}".encode("ascii"))
  return b"\r\n".join(lines)


def rewrite_request(headers, external_host):
  upstream_host = f"{UPSTREAM_HOST}:{UPSTREAM_PORT}"
  return replace_header(headers, "Host", upstream_host), external_host or upstream_host


def relay_raw(upstream):
  selector = selectors.DefaultSelector()
  selector.register(sys.stdin.buffer, selectors.EVENT_READ, upstream)
  selector.register(upstream, selectors.EVENT_READ, sys.stdout.buffer)

  while selector.get_map():
    for key, _ in selector.select():
      target = key.data
      data = os.read(key.fileobj.fileno(), 65536)
      if not data:
        selector.unregister(key.fileobj)
        try:
          target.flush()
        except AttributeError:
          pass
        try:
          target.shutdown(socket.SHUT_WR)
        except (AttributeError, OSError):
          pass
        continue
      if isinstance(target, socket.socket):
        target.sendall(data)
      else:
        target.write(data)
        target.flush()


def read_response(upstream, initial):
  data = initial
  headers, rest = split_headers(data)
  while not rest and b"\r\n\r\n" not in data:
    chunk = upstream.recv(65536)
    if not chunk:
      return data
    data += chunk
    headers, rest = split_headers(data)

  content_length = None
  for line in headers.split(b"\r\n"):
    if line.lower().startswith(b"content-length:"):
      content_length = int(line.split(b":", 1)[1].strip())
      break

  if content_length is None:
    while True:
      chunk = upstream.recv(65536)
      if not chunk:
        break
      data += chunk
    return data

  while len(rest) < content_length:
    chunk = upstream.recv(65536)
    if not chunk:
      break
    rest += chunk

  return headers + rest


request = read_until_headers(0)
request_headers, request_body = split_headers(request)
external_host = get_header(request_headers, "Host")
request_headers, external_host = rewrite_request(request_headers, external_host)

with socket.create_connection((UPSTREAM_HOST, UPSTREAM_PORT)) as upstream:
  upstream.sendall(request_headers + request_body)
  response = upstream.recv(65536)

  if b"\r\nUpgrade: websocket\r\n" in response or b"\r\nupgrade: websocket\r\n" in response.lower():
    os.write(1, response)
    relay_raw(upstream)
  else:
    response = read_response(upstream, response)
    response = response.replace(
      f"127.0.0.1:{EXTERNAL_PORT}".encode("ascii"),
      external_host.encode("ascii"),
    ).replace(
      f"127.0.0.1:{UPSTREAM_PORT}".encode("ascii"),
      external_host.encode("ascii"),
    )
    headers, body = split_headers(response)
    if b"content-length:" in headers.lower():
      headers = replace_header(headers, "Content-Length", str(len(body)))
    os.write(1, headers + body)
PY

socat TCP-LISTEN:9222,fork,reuseaddr,bind=0.0.0.0 EXEC:"python3 /tmp/hermes-cdp-forwarder.py",nofork &

exec /usr/bin/chromium \
  --headless=new \
  --disable-gpu \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9223 \
  --user-data-dir=/data \
  about:blank
