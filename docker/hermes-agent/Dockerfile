FROM docker.io/nousresearch/hermes-agent:latest AS hermes-bootstrap-runtime

USER root

ARG ARTICLE_COLLECTOR_VERSION=v0.6.17
ARG GOOGLE_CALENDAR_MCP_VERSION=2.6.2
ARG GOOGLE_GMAIL_MCP_VERSION=1.2.3
ARG HINDSIGHT_CLIENT_VERSION=0.6.1

COPY xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp
COPY gh-wrapper.sh /usr/local/bin/gh
COPY bootstrap/hermes_bootstrap /usr/local/lib/hermes-bootstrap/hermes_bootstrap
COPY bootstrap-manifest.yaml /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
COPY hermes-bootstrap /usr/local/bin/hermes-bootstrap
COPY hindsight_acceptance.py /usr/local/bin/hermes-hindsight-acceptance
RUN chmod 0755 /usr/local/bin/hermes-hindsight-acceptance

RUN python3 - <<'PY'
import re
from pathlib import Path

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one pinned source match in {path}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def replace_pattern_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"expected exactly one pinned source match in {path}")
    path.write_text(updated, encoding="utf-8")


replace_once(
    Path("/opt/hermes/gateway/channel_directory.py"),
    'types="public_channel,private_channel",',
    'types="public_channel",',
)
replace_pattern_once(
    Path("/opt/hermes/toolsets.py"),
    r'("browser_dialog"(?:,\s*"browser_exec")?),\s*"web_search"',
    r'\1',
)
replace_once(
    Path("/opt/hermes/plugins/platforms/discord/adapter.py"),
    '''    def _self_is_explicitly_mentioned(self, message: Any) -> bool:
        """Return True when this bot is explicitly @mentioned in the message.

        Treats the bot as mentioned if it is either present in the resolved
        ``message.mentions`` list OR referenced by its raw ``<@ID>`` / ``<@!ID>``
        form in the message content.
        """
        if not self._client or not self._client.user:
            return False
        if self._client.user in getattr(message, "mentions", []):
            return True
        return str(self._client.user.id) in self._raw_mentioned_user_ids(message)
''',
    '''    def _self_is_explicitly_mentioned(self, message: Any) -> bool:
        """Return True when this bot is explicitly @mentioned in the message.

        In addition to direct user mentions, Discord creates a managed role
        for each bot.  Discord renders that role as the bot's display name,
        but sends it as ``<@&ROLE_ID>`` and leaves ``message.mentions`` empty.
        Treat only a managed role owned by this bot as an equivalent mention;
        ordinary role mentions must not wake the bot.
        """
        if not self._client or not self._client.user:
            return False
        if self._client.user in getattr(message, "mentions", []):
            return True
        if str(self._client.user.id) in self._raw_mentioned_user_ids(message):
            return True

        bot_id = int(self._client.user.id)
        role_mentions = list(getattr(message, "role_mentions", []))
        raw_role_ids = re.findall(r"<@&([0-9]+)>", getattr(message, "content", "") or "")
        guild = getattr(message, "guild", None)
        get_role = getattr(guild, "get_role", None)
        if callable(get_role):
            for raw_role_id in raw_role_ids:
                role = get_role(int(raw_role_id))
                if role is not None:
                    role_mentions.append(role)

        return any(
            getattr(getattr(role, "tags", None), "bot_id", None) == bot_id
            for role in role_mentions
        )
''',
)
PY

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gh gnupg \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
    amd64|arm64) ;; \
    *) echo "unsupported architecture for 1Password CLI: $arch" >&2; exit 1 ;; \
  esac \
  && install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d \
  && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor --batch --yes -o /usr/share/keyrings/1password-archive-keyring.gpg \
  && printf 'deb [arch=%s signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\n' "$arch" "$arch" > /etc/apt/sources.list.d/1password.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends 1password-cli \
  && op --version \
  && case "$arch" in \
    amd64) article_collector_asset="article-collector-linux-amd64" ;; \
    arm64) article_collector_asset="article-collector-linux-arm64" ;; \
  esac \
  && curl -fsSL \
    "https://github.com/rurusasu/article-collector/releases/download/${ARTICLE_COLLECTOR_VERSION}/${article_collector_asset}" \
    -o /usr/local/bin/article-collector \
  && chmod 0755 /usr/local/bin/article-collector \
  && /usr/bin/gh --version \
  && npm --version \
  && npx --version \
  && npm install --global --omit=dev --no-audit --no-fund \
    "@cocal/google-calendar-mcp@${GOOGLE_CALENDAR_MCP_VERSION}" \
    "@artymclabin/gmail-mcp@${GOOGLE_GMAIL_MCP_VERSION}" \
  && google-calendar-mcp --version \
  && npm list --global --depth=0 "@artymclabin/gmail-mcp@${GOOGLE_GMAIL_MCP_VERSION}" \
  && article-collector --help \
  && uv pip install --python /opt/hermes/.venv/bin/python \
      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}" \
  && /opt/hermes/.venv/bin/python -c \
      "from importlib.metadata import version; assert version('hindsight-client') == '${HINDSIGHT_CLIENT_VERSION}'" \
  && chmod 0755 /usr/local/bin/gh \
  && chmod 0755 /usr/local/bin/hermes-xapi-mcp \
  && chmod 0755 /usr/local/bin/hermes-bootstrap \
  && rm -rf /var/lib/apt/lists/*

FROM hermes-bootstrap-runtime AS hermes-bootstrap-test

WORKDIR /workspace

COPY Dockerfile /workspace/docker/hermes-agent/Dockerfile
COPY compose.yml /workspace/docker/hermes-agent/compose.yml
COPY hindsight.env /workspace/docker/hermes-agent/hindsight.env
COPY bootstrap-manifest.yaml /workspace/docker/hermes-agent/bootstrap-manifest.yaml
COPY hindsight_acceptance.py /workspace/docker/hermes-agent/hindsight_acceptance.py
COPY bootstrap/tests /workspace/docker/hermes-agent/bootstrap/tests

RUN PYTHONPATH=/usr/local/lib/hermes-bootstrap /opt/hermes/.venv/bin/python -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests

FROM hermes-bootstrap-runtime

WORKDIR /
