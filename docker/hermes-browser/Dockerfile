FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN test "$(dpkg --print-architecture)" = "amd64" \
  && apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && install -d -m 0755 /etc/apt/keyrings \
  && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    -o /etc/apt/keyrings/google-chrome.asc \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends google-chrome-stable fonts-noto-cjk locales socat python3-minimal xvfb x11vnc x11-utils novnc websockify \
  && sed -i 's/^# *\(ja_JP.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --system --gid 997 hermes-browser \
  && useradd --system --uid 997 --create-home --gid hermes-browser hermes-browser \
  && install -d -o hermes-browser -g hermes-browser /data \
  && sed -i 's#</body>#  <script type="module" src="app/clipboard-paste.js?v=5"></script>\n</body>#' /usr/share/novnc/vnc.html \
  && ln -sf vnc.html /usr/share/novnc/index.html

ENV LANG=ja_JP.UTF-8 \
  LANGUAGE=ja_JP:ja \
  LC_ALL=ja_JP.UTF-8

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY clipboard-paste.js /usr/share/novnc/app/clipboard-paste.js

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

USER hermes-browser

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
