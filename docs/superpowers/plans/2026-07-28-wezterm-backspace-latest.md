# WezTerm Backspace and macOS Nightly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Backspace after the WezTerm leader key and install the continuously updated WezTerm nightly cask on macOS.

**Architecture:** Keep terminal behavior in the WezTerm Lua configuration and package-provider selection in the existing catalog. Darwin uses the official `wezterm@nightly` Homebrew cask and excludes the Nix WezTerm package, while Linux and Windows retain their current providers.

**Tech Stack:** Lua, Nix, nix-darwin, Homebrew casks, Pester, Bats

## Global Constraints

- Keep `Ctrl+Space` as the WezTerm leader with its existing timeout.
- Preserve the Linux Nix provider and Windows nightly winget provider.
- Use the existing nix-darwin activation-time Homebrew update and upgrade path.
- Do not add a second updater.

---

### Task 1: Leader Backspace Passthrough

**Files:**

- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `chezmoi/terminals/wezterm/wezterm.lua`

**Interfaces:**

- Consumes: WezTerm `LEADER` modifier and `act.SendKey`
- Produces: A `LEADER+Backspace` assignment that sends an unmodified Backspace event

- [ ] **Step 1: Write the failing keybinding contract**

Add this assertion to the existing WezTerm keybinding test:

```powershell
$content | Should -Match 'key = "Backspace", mods = "LEADER", action = act\.SendKey\(\{ key = "Backspace" \}\)'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -Output Detailed"
```

Expected: the WezTerm keybinding test fails because the leader Backspace assignment is absent.

- [ ] **Step 3: Add the minimal WezTerm assignment**

Add this entry immediately after the Shift+Enter assignment:

```lua
{ key = "Backspace", mods = "LEADER", action = act.SendKey({ key = "Backspace" }) },
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: all tests in `Keybindings.Tests.ps1` pass.

### Task 2: macOS WezTerm Nightly Provider

**Files:**

- Modify: `tests/bash/package_catalog.bats`
- Modify: `nix/packages/sets.nix`

**Interfaces:**

- Consumes: package catalog `pkg` and `support` metadata
- Produces: Darwin cask `wezterm@nightly`, Linux Nix provider, existing Windows winget provider

- [ ] **Step 1: Write the failing catalog and evaluation contract**

Add a Bats test that extracts the WezTerm catalog entry and requires:

```nix
pkg = if pkgs.stdenv.isDarwin then null else pkgs.wezterm;
support.darwin.provider = "homebrew-cask";
support.darwin.cask = "wezterm@nightly";
support.linux.provider = "nix";
```

The test must also evaluate `darwinConfigurations.macos` and assert that the
normalized Homebrew cask list contains `wezterm@nightly` while the Home Manager
package list contains no package whose `pname` is `wezterm`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bats tests/bash/package_catalog.bats
```

Expected: the new WezTerm provider test fails because Darwin still resolves the Nix package and has no WezTerm cask.

- [ ] **Step 3: Implement the provider metadata**

Change the WezTerm entry to:

```nix
wezterm = {
  pkg = if pkgs.stdenv.isDarwin then null else pkgs.wezterm;
  winget = "wez.wezterm.nightly";
  category = "terminal";
  support = {
    darwin = {
      provider = "homebrew-cask";
      cask = "wezterm@nightly";
    };
    linux = {
      provider = "nix";
    };
  };
};
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: all package catalog tests pass.

### Task 3: Final Verification

**Files:**

- Verify all modified implementation and test files

**Interfaces:**

- Consumes: completed Tasks 1 and 2
- Produces: formatted, evaluated, regression-tested branch

- [ ] **Step 1: Format**

Run:

```bash
nix fmt
```

- [ ] **Step 2: Run relevant tests**

Run:

```bash
bats tests/bash/package_catalog.bats tests/bash/macos_config.bats
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: Evaluate the macOS configuration**

Run:

```bash
DOTFILES_USER=codex DOTFILES_HOME=/Users/codex nix eval --impure --json .#darwinConfigurations.macos.config.homebrew.casks
DOTFILES_USER=codex DOTFILES_HOME=/Users/codex nix build --no-link .#darwinConfigurations.macos.system
```

- [ ] **Step 4: Review the final diff**

Run:

```bash
git diff --check
git diff origin/main...HEAD
```
