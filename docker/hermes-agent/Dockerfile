FROM docker.io/nousresearch/hermes-agent:latest AS hermes-bootstrap-runtime

USER root

ARG ARTICLE_COLLECTOR_VERSION=v0.6.17
ARG GOOGLE_CALENDAR_MCP_VERSION=2.6.2
ARG GOOGLE_GMAIL_MCP_VERSION=1.2.3
ARG HINDSIGHT_CLIENT_VERSION=0.6.1
ARG HERMES_LCM_VERSION=v0.20.0
ARG HERMES_LCM_COMMIT=49e99a272d2d461e5c90732e7ef2bc20e96f0826

COPY hermes-agent/xapi-mcp.sh /usr/local/bin/hermes-xapi-mcp
COPY hermes-agent/gh-wrapper.sh /usr/local/bin/gh
COPY hermes-agent/bootstrap/hermes_bootstrap /usr/local/lib/hermes-bootstrap/hermes_bootstrap
COPY hermes-agent/bootstrap-manifest.yaml /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml
COPY hermes-agent/hermes-bootstrap /usr/local/bin/hermes-bootstrap
COPY hermes-agent/hindsight_acceptance.py /usr/local/bin/hermes-hindsight-acceptance
COPY hermes-agent/gateway_convergence.py /usr/local/bin/hermes-gateway-converge
COPY hermes-agent/hermes_storage_seed.py /usr/local/bin/hermes-storage-seed
RUN chmod 0755 /usr/local/bin/hermes-hindsight-acceptance
RUN chmod 0755 /usr/local/bin/hermes-gateway-converge
RUN chmod 0755 /usr/local/bin/hermes-storage-seed

RUN python3 - <<'PY'
import re
from pathlib import Path

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one pinned source match in {path}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def replace_pattern_variant_once(path: Path, variants: list[tuple[str, str]]) -> None:
    text = path.read_text(encoding="utf-8")
    matches = [
        (pattern, replacement)
        for pattern, replacement in variants
        if len(re.findall(pattern, text)) == 1
    ]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one pinned source variant in {path}")
    pattern, replacement = matches[0]
    path.write_text(re.sub(pattern, replacement, text, count=1), encoding="utf-8")


def replace_variant_once(path: Path, variants: list[tuple[str, str]]) -> None:
    text = path.read_text(encoding="utf-8")
    matches = [(old, new) for old, new in variants if text.count(old) == 1]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one pinned source variant in {path}")
    old, new = matches[0]
    path.write_text(text.replace(old, new), encoding="utf-8")


replace_once(
    Path("/opt/hermes/gateway/channel_directory.py"),
    'types="public_channel,private_channel",',
    'types="public_channel",',
)
replace_pattern_variant_once(
    Path("/opt/hermes/toolsets.py"),
    [
        (
            r'("browser_dialog"(?:,\s*"browser_exec")?),\s*"web_search"',
            r'\1',
        ),
        (
            r'(\[t for t in _HERMES_CORE_TOOLS if t\.startswith\("browser_"\)\])\s*\+\s*\["web_search"\]',
            r'\1',
        ),
    ],
)
replace_variant_once(
    Path("/opt/hermes/plugins/platforms/discord/adapter.py"),
    [
        (
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
        ),
        (
            '''    def _self_is_explicitly_mentioned(self, message: Any) -> bool:
        """True when the bot is in ``message.mentions`` or raw-mentioned in the content."""
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
        ),
    ],
)
PY

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git gh gnupg \
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

RUN git clone --quiet --depth 1 --branch "${HERMES_LCM_VERSION}" \
    https://github.com/stephenschoettler/hermes-lcm \
    /opt/hermes/plugins/hermes-lcm \
  && test "$(git -C /opt/hermes/plugins/hermes-lcm rev-parse HEAD)" = "${HERMES_LCM_COMMIT}" \
  && /opt/hermes/.venv/bin/python -m py_compile /opt/hermes/plugins/hermes-lcm/__init__.py \
  && rm -rf /opt/hermes/plugins/hermes-lcm/.git

RUN /opt/hermes/.venv/bin/python -c \
      'import os; os.environ["HERMES_HOME"] = "/tmp/hermes-lcm-build-check"; from pathlib import Path; home = Path(os.environ["HERMES_HOME"]); home.mkdir(parents=True, exist_ok=True); (home / "config.yaml").write_text("plugins:\n  enabled:\n    - hermes-lcm\ncontext:\n  engine: lcm\n", encoding="utf-8"); from hermes_cli.plugins import discover_plugins, get_plugin_context_engine; discover_plugins(force=True); engine = get_plugin_context_engine(); assert engine is not None and engine.name == "lcm"' \
  && rm -rf /tmp/hermes-lcm-build-check

FROM hermes-bootstrap-runtime AS hermes-bootstrap-test

WORKDIR /workspace

COPY hermes-agent/Dockerfile /workspace/docker/hermes-agent/Dockerfile
COPY hermes-service/compose.yml /workspace/docker/hermes-service/compose.yml
COPY local-ai-services/compose.yml /workspace/docker/local-ai-services/compose.yml
COPY hindsight/hindsight.env /workspace/docker/hindsight/hindsight.env
COPY hermes-agent/bootstrap-manifest.yaml /workspace/docker/hermes-agent/bootstrap-manifest.yaml
COPY hermes-agent/hindsight_acceptance.py /workspace/docker/hermes-agent/hindsight_acceptance.py
COPY hermes-agent/gateway_convergence.py /workspace/docker/hermes-agent/gateway_convergence.py
COPY hermes-agent/hermes_storage_seed.py /workspace/docker/hermes-agent/hermes_storage_seed.py
COPY hermes-agent/tests /workspace/docker/hermes-agent/tests
COPY hermes-agent/bootstrap/tests /workspace/docker/hermes-agent/bootstrap/tests

RUN PYTHONPATH=/usr/local/lib/hermes-bootstrap /opt/hermes/.venv/bin/python -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests \
  -p 'test_[!t]*.py'

RUN PYTHONPATH=/workspace/docker/hermes-agent /opt/hermes/.venv/bin/python -m unittest \
  /workspace/docker/hermes-agent/tests/test_hermes_storage_seed.py

RUN PYTHONPATH=/usr/local/lib/hermes-bootstrap /opt/hermes/.venv/bin/python -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests \
  -p 'test_t*.py'

RUN PYTHONPATH=/usr/local/lib/hermes-bootstrap /opt/hermes/.venv/bin/python -m unittest discover \
  -s /workspace/docker/hermes-agent/bootstrap/tests \
  -p 'hindsight_real_provider_gate.py' -v

FROM hermes-bootstrap-runtime

WORKDIR /
