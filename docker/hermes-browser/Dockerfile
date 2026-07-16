FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends chromium chromium-sandbox socat python3-minimal curl ca-certificates xvfb x11vnc novnc websockify \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --system hermes-browser \
  && useradd --system --create-home --gid hermes-browser hermes-browser \
  && install -d -o hermes-browser -g hermes-browser /data

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

USER hermes-browser

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
