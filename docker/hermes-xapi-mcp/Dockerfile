FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev --ignore-scripts

COPY entrypoint.sh /usr/local/bin/hermes-xapi-mcp

ENV NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false

RUN chmod 0755 /usr/local/bin/hermes-xapi-mcp

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=12 \
  CMD node -e "const net=require('node:net');const s=net.connect({host:'127.0.0.1',port:8080},()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);"
