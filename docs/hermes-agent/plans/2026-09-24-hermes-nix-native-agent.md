# Hermes Nix-Native Agent Implementation Plan

> **Status:** Implementation is in the current PR worktree; GitHub Actions verification is pending.

**Goal:** Manage the Hermes Agent CLI and gateway as a Nix/Home Manager user service on macOS and Linux/WSL while retaining the existing Hermes state path.

**Architecture:** Pin the upstream Hermes Agent flake as `inputs.hermes-agent`. Add a focused Home Manager module for package selection, `HERMES_HOME`, and native systemd-user/launchd lifecycle; leave Docker-based sidecars and bootstrap behavior explicitly outside the native Agent service.

**Tech Stack:** Nix flake inputs, Home Manager, nix-unit.

**Spec:** Manage the Hermes Agent with Nix on macOS and Linux/WSL, retain its existing state path, and make the native WSL service setup an end-to-end CI check.

## Global Constraints

- Do not replace or overwrite existing Hermes runtime state or secrets during Home Manager activation.
- Keep Docker sidecars and bootstrap ownership distinct from the native Agent process.
- Do not automatically migrate or delete the existing Docker `hermes-data` volume; a data migration requires a separate backup and conflict policy.
- Nix option and package selection contracts must use nix-unit.

## Review Focus

- Feature disabled: no Hermes package or native service is selected.
- Linux/WSL: the user service uses the locked package and the existing `~/.hermes` state path.
- macOS: a launchd user agent uses the same CLI and state path.
- Secrets: no secret value or secret file content is evaluated into the Nix store.
- Migration boundary: docs must not claim profile bootstrap, container sidecars, or old volume data migrate automatically.

---

### Task 1: Home Manager Hermes service contract

**Files:**

- Create: `nix/tests/hermes-agent.nix`
- Modify: `nix/flakes/tests.nix`
- Modify: `nix/test-fixtures.nix` and Nix-unit contract assertions

- [x] Add nix-unit assertions for disabled, Linux/WSL, and macOS profile behavior.
- [x] Register the test module in the authoritative nix-unit test set.
- [ ] Run the focused nix-unit test and full `nix flake check` in CI (Nix is unavailable on the local Windows host).

### Task 2: Native user-level Agent management

**Files:**

- Create: `nix/home/hermes-agent.nix`
- Modify: `nix/home/darwin.nix`
- Modify: `nix/home/linux.nix`
- Modify: `nix/home/wsl.nix`
- Modify: `flake.nix` and `.github/workflows/ci-bootstrap.yml`
- Modify: `scripts/powershell/ci/Invoke-NixosWslE2E.ps1`

- [x] Add the pinned package, shared Hermes home, and platform-native gateway unit.
- [x] Add a hosted WSL E2E that enables Hermes through Nix, preserves pre-existing state, and checks the gateway service.
- [ ] Verify the generated flake lock, formatting, nix-unit, and full relevant Nix checks in CI.

### Task 3: Document management and migration boundaries

**Files:**

- Modify: `docs/hermes-agent/bootstrap.md`
- Modify: `docs/architecture.md`

- [x] Explain Nix ownership of the CLI/gateway, retained container sidecars/bootstrap, and manual state-volume migration boundary.
- [x] Verify links and ensure documentation does not imply all Hermes containers are removed.
