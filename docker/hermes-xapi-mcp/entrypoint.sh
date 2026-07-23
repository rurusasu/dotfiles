#!/bin/sh
set -eu

if [ -n "${X_API_CLIENT_ID:-}" ]; then
  export CLIENT_ID="$X_API_CLIENT_ID"
fi

if [ -n "${X_API_CLIENT_SECRET:-}" ]; then
  export CLIENT_SECRET="$X_API_CLIENT_SECRET"
fi

exec node_modules/.bin/xurl mcp https://api.x.com/mcp
