FROM docker.io/nousresearch/hermes-agent@sha256:dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731 AS hermes-bootstrap-runtime

USER root

ARG ARTICLE_COLLECTOR_VERSION=v0.6.17

COPY xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp
COPY gh-wrapper.sh /usr/local/bin/gh
COPY bootstrap/hermes_bootstrap /usr/local/lib/hermes-bootstrap/hermes_bootstrap
COPY bootstrap-manifest.yaml /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
COPY hermes-bootstrap /usr/local/bin/hermes-bootstrap

RUN python3 - <<'PY'
from pathlib import Path

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one pinned source match in {path}")
    path.write_text(text.replace(old, new), encoding="utf-8")


replace_once(
    Path("/opt/hermes/gateway/channel_directory.py"),
    'types="public_channel,private_channel",',
    'types="public_channel",',
)
replace_once(
    Path("/opt/hermes/toolsets.py"),
    '"browser_dialog", "web_search"',
    '"browser_dialog"',
)
replace_once(
    Path("/opt/hermes/hermes_cli/profile_distribution.py"),
    """\
    target.mkdir(parents=True, exist_ok=True)

    for entry in staged.iterdir():
        name = entry.name
""",
    """\
    target.mkdir(parents=True, exist_ok=True)

    owned_roots = {
        Path(path).parts[0]
        for path in manifest.owned_paths()
        if Path(path).parts
    }
    for entry in staged.iterdir():
        name = entry.name

        if name not in owned_roots and name != ENV_TEMPLATE_FILENAME:
            continue
""",
)
PY

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gh \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
    amd64) article_collector_asset="article-collector-linux-amd64" ;; \
    arm64) article_collector_asset="article-collector-linux-arm64" ;; \
    *) echo "unsupported architecture for article-collector: $arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL \
    "https://github.com/rurusasu/article-collector/releases/download/${ARTICLE_COLLECTOR_VERSION}/${article_collector_asset}" \
    -o /usr/local/bin/article-collector \
  && chmod 0755 /usr/local/bin/article-collector \
  && /usr/bin/gh --version \
  && npm --version \
  && npx --version \
  && article-collector --help \
  && chmod 0755 /usr/local/bin/gh \
  && chmod 0755 /usr/local/bin/hermes-xapi-mcp \
  && chmod 0755 /usr/local/bin/hermes-bootstrap \
  && rm -rf /var/lib/apt/lists/*

FROM hermes-bootstrap-runtime AS hermes-bootstrap-test

WORKDIR /workspace

COPY Dockerfile /workspace/docker/hermes-agent/Dockerfile
COPY compose.yml /workspace/docker/hermes-agent/compose.yml
COPY bootstrap-manifest.yaml /workspace/docker/hermes-agent/bootstrap-manifest.yaml
COPY bootstrap/tests /workspace/docker/hermes-agent/bootstrap/tests

RUN PYTHONPATH=/usr/local/lib/hermes-bootstrap /opt/hermes/.venv/bin/python -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests

FROM hermes-bootstrap-runtime

WORKDIR /
