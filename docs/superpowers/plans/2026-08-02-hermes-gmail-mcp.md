# Hermes Gmail MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add official Gmail MCP OAuth access to every managed Hermes profile, limited to Gmail read/search and draft creation, then verify it through each profile's Discord bot.

**Architecture:** Add a remote HTTP `mcp_servers.gmail` entry to the root and all managed profile configurations. The entry uses Hermes native OAuth PKCE, the existing Calendar OAuth client ID/secret exposed through private profile environment files, and an explicit allowlist containing only Gmail read and draft tools.

**Tech Stack:** Hermes Agent v0.18.2, Google Gmail remote MCP Developer Preview, Python bootstrap package, YAML config, Bash/PowerShell Taskfile adapters, Bats and Python unittest.

## Global Constraints

- Gmail endpoint: `https://gmailmcp.googleapis.com/mcp/v1`.
- OAuth scopes: `https://www.googleapis.com/auth/gmail.readonly` and `https://www.googleapis.com/auth/gmail.compose`.
- Allowed tools: `search_threads`, `get_thread`, `get_message`, `list_labels`, `list_drafts`, `create_draft`.
- Disallowed actions: send, delete, and label mutation.
- OAuth client secrets stay in private runtime environment values derived from the existing Calendar OAuth credential item.
- Verification must cover default plus every currently managed named profile through actual Discord replies.

---

### Task 1: Add failing Gmail MCP contract tests

**Files:**

- Create: `tests/bash/hermes_gmail_mcp.bats`
- Modify: `docker/hermes-agent/bootstrap/tests/test_envfiles.py`
- Modify: `docker/hermes-agent/bootstrap/tests/test_google_calendar.py`
- Create: `docker/hermes-agent/bootstrap/tests/test_google_gmail.py`

**Interfaces:**

- Tests define the expected `gmail` server URL, OAuth scope string, tool allowlist, and `GMAIL_MCP_CLIENT_ID` / `GMAIL_MCP_CLIENT_SECRET` environment keys.
- Tests define `install_google_gmail_configurations(targets, transaction)` and `validate_google_gmail_installation(data_root, targets)` as the bootstrap boundary.

- [ ] **Step 1: Write the failing shell contract tests**

  Assert that the source declares the official Gmail MCP URL, `auth: oauth`, both Gmail scopes, all six allowed tools, and no send/delete/label mutation tool names.

- [ ] **Step 2: Write the failing Python configuration tests**

  Add tests for inserting the Gmail MCP entry into every target config, preserving unrelated servers, rejecting a missing or altered entry, and rejecting a missing OAuth scope or forbidden tool.

- [ ] **Step 3: Write the failing environment tests**

  Extend the profile environment expectation to include the two Gmail client variables derived from the Calendar OAuth JSON, and assert that the values are redacted in representations and remain private environment assignments.

- [ ] **Step 4: Run the focused tests and confirm the expected failures**

  Run `bats tests/bash/hermes_gmail_mcp.bats` and `PYTHONPATH=docker/hermes-agent/bootstrap python3 -m unittest docker.hermes-agent.bootstrap.tests.test_google_gmail docker.hermes-agent.bootstrap.tests.test_envfiles -v`.

  Expected result: the new tests fail because the Gmail module, configuration, and environment values do not exist yet.

### Task 2: Implement Gmail configuration and OAuth client propagation

**Files:**

- Create: `docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py`
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/payload.py`
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/envfiles.py`
- Modify: `docker/hermes-agent/bootstrap/hermes_bootstrap/app.py`
- Modify: `docker/hermes-agent/bootstrap/tests/test_payload.py`
- Modify: `docker/hermes-agent/bootstrap/tests/test_app.py`

**Interfaces:**

- `google_gmail.py` exports `install_google_gmail_configurations(targets, transaction)` and `validate_google_gmail_installation(data_root, targets)`.
- `envfiles.py` exports the existing `build_profile_environment` behavior with `GMAIL_MCP_CLIENT_ID` and `GMAIL_MCP_CLIENT_SECRET` added for root and every named profile.
- `payload.py` continues to consume the existing `google_calendar` secret and parses its `installed.client_id` and `installed.client_secret` without adding a new secret item.

- [ ] **Step 1: Implement the minimal Gmail config constants and installer**

  Use the exact server entry below and write it into each managed `config.yaml`:

  ```yaml
  gmail:
    url: https://gmailmcp.googleapis.com/mcp/v1
    auth: oauth
    connect_timeout: 315
    oauth:
      client_id: ${GMAIL_MCP_CLIENT_ID}
      client_secret: ${GMAIL_MCP_CLIENT_SECRET}
      scope: https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.compose
    tools:
      include:
        - search_threads
        - get_thread
        - get_message
        - list_labels
        - list_drafts
        - create_draft
      resources: false
      prompts: false
  ```

- [ ] **Step 2: Add OAuth client extraction and validation**

  Parse the existing Calendar OAuth JSON, require non-empty `installed.client_id` and `installed.client_secret`, and expose them only through the private environment mapping. Never include the values in YAML, logs, exception messages, or test output.

- [ ] **Step 3: Wire installation and final validation into bootstrap**

  Install the Gmail config after Calendar config installation and validate it for root/default and every manifest profile before bootstrap reports success.

- [ ] **Step 4: Run the focused tests and make them pass**

  Run `PYTHONPATH=docker/hermes-agent/bootstrap python3 -m unittest docker.hermes-agent.bootstrap.tests.test_google_gmail docker.hermes-agent.bootstrap.tests.test_envfiles docker.hermes-agent.bootstrap.tests.test_payload docker.hermes-agent.bootstrap.tests.test_app -v`.

### Task 3: Add authentication and runtime verification commands

**Files:**

- Create: `scripts/sh/hermes-gmail.sh`
- Create: `scripts/powershell/hermes-gmail.ps1`
- Modify: `Taskfile.yml`
- Create: `tests/bash/hermes_gmail_auth.bats`
- Create: `docs/hermes-agent/gmail-mcp.md`

**Interfaces:**

- Unix command: `scripts/sh/hermes-gmail.sh auth profile-name`, `scripts/sh/hermes-gmail.sh test profile-name`.
- Windows command: `scripts/powershell/hermes-gmail.ps1 -Action auth -Profile profile-name` and `-Action test`.
- Task commands: `task hermes:gmail:auth PROFILE=profile-name` and `task hermes:gmail:test PROFILE=profile-name`.

- [ ] **Step 1: Write failing command contract tests**

  Assert profile validation, use of `HERMES_HOME=/opt/data/profiles/profile-name`, invocation of `hermes mcp login gmail`, no token value in arguments, and a failure when the profile token cache is absent after login.

- [ ] **Step 2: Implement the Unix adapter**

  Validate the profile against the mounted profile directory, run the interactive Hermes OAuth login with a 315-second callback window, and check only token-file existence and private mode. Do not print token contents.

- [ ] **Step 3: Implement the PowerShell adapter and Taskfile entries**

  Mirror the Unix behavior through native Docker Compose execution and preserve the repository's Windows adapter conventions.

- [ ] **Step 4: Document Google Cloud prerequisites and callback behavior**

  Document Gmail API/MCP API enablement, Gmail OAuth consent scopes, reuse of the Calendar OAuth client, browser consent, per-profile login, and the exact no-send/no-delete boundary.

- [ ] **Step 5: Run command contract tests**

  Run `bats tests/bash/hermes_gmail_auth.bats` and the corresponding PowerShell test suite when available.

### Task 4: Build, bootstrap, and verify all profiles through Discord

**Files:**

- Modify: `docs/hermes-agent/gmail-mcp.md`
- Modify: `tests/bash/bootstrap_acceptance.bats`

**Interfaces:**

- Runtime target is the real `hermes` Compose stack and its Discord gateway.
- Profile set is discovered from `/opt/data/profiles` plus the root/default profile; no single profile is treated as representative.

- [ ] **Step 1: Run repository validation before live auth**

  Run `bats tests/bash/hermes_gmail_mcp.bats tests/bash/hermes_gmail_auth.bats tests/bash/bootstrap_acceptance.bats`, the full bootstrap unittest discovery, `docker compose -f docker/hermes-agent/compose.yml config --quiet`, and `pre-commit run --all-files`.

- [ ] **Step 2: Rebuild and apply the Hermes stack**

  Run `task hermes:bootstrap`, confirm the root and every named profile contains the Gmail MCP declaration, confirm `tests/bash/bootstrap_acceptance.bats` sees the Gmail entry, and confirm no client secret appears in config files or logs.

- [ ] **Step 3: Complete OAuth once per profile**

  Run `task hermes:gmail:auth PROFILE=profile-name` serially for `default`, `hoffman`, `kuroda`, `nancy`, `rick`, `risarisa`, and `shiraishi`, completing the browser consent flow and checking the token cache after every profile.

- [ ] **Step 4: Verify MCP discovery per profile**

  Run `docker exec hermes hermes -p profile-name mcp test gmail` for `default`, `hoffman`, `kuroda`, `nancy`, `rick`, `risarisa`, and `shiraishi`, and confirm the discovered tool set contains exactly the six allowed tools.

- [ ] **Step 5: Verify through each Discord bot**

  Send an individual Discord DM to every profile bot asking it to search a narrow harmless query, retrieve a matching thread when available, list drafts, and create a test draft to `noreply@example.com` titled `[Hermes Gmail OAuth test]`. Read each bot's actual reply and record success/failure per profile.

- [ ] **Step 6: Confirm the safety boundary**

  Confirm no test sends the draft and that the discovered tool list contains no send, delete, label, or unlabel operation. Report any profile lacking an actual Discord reply as unverified.
