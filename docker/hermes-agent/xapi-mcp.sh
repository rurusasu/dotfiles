#!/bin/sh
set -eu

if [ "${X_API_CLIENT_ID:-}" != "" ] && [ "${X_API_CLIENT_ID}" != '${X_API_CLIENT_ID}' ]; then
  export CLIENT_ID="${X_API_CLIENT_ID}"
fi

if [ "${X_API_CLIENT_SECRET:-}" != "" ] && [ "${X_API_CLIENT_SECRET}" != '${X_API_CLIENT_SECRET}' ]; then
  export CLIENT_SECRET="${X_API_CLIENT_SECRET}"
fi

exec npx -y @xdevplatform/xurl mcp https://api.x.com/mcp
