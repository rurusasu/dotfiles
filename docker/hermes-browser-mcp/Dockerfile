FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev

ENV CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1 \
    CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NODE_ENV=production

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/ping').then((response)=>process.exit(response.ok?0:1)).catch(()=>process.exit(1))"

USER node

CMD ["node_modules/.bin/mcp-proxy", "--server", "stream", "--host", "0.0.0.0", "--port", "8080", "--", "node_modules/.bin/chrome-devtools-mcp", "--browser-url=http://chromium:9222", "--no-usage-statistics"]
