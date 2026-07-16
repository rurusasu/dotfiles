FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends chromium chromium-sandbox socat python3-minimal curl ca-certificates xvfb x11vnc x11-utils novnc websockify \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --system hermes-browser \
  && useradd --system --create-home --gid hermes-browser hermes-browser \
  && install -d -o hermes-browser -g hermes-browser /data \
  && ln -sf vnc.html /usr/share/novnc/index.html

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

USER hermes-browser

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
