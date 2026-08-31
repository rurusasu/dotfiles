# nix-darwin Provider Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 13 Darwin Homebrew package providers with verified Nix derivations, preserve optional install profiles, and add automatic version/provider promotion Pull Requests.

**Architecture:** `nix/packages/sets.nix` remains the package catalog SSOT and resolves only the provider selected for the active platform and install profile. Upstream packages come directly from the locked nixpkgs; Dia, Orca, Hammerspoon, and Docker Desktop use fixed-output Darwin derivations. A macOS verifier validates the Nix result before a migration adapter removes the legacy Homebrew package. A scheduled Apple Silicon workflow proposes version/provider changes as reviewable Pull Requests instead of switching during local evaluation.

**Tech Stack:** Nix 2.x, nix-darwin, Home Manager, Go Task, Bash 3.2-compatible adapters, Python 3.14, Bats 1.13, GitHub Actions `macos-26`, `jq`, `codesign`, `spctl`, `PlistBuddy`.

**Spec:** `docs/superpowers/specs/2026-08-27-nix-darwin-provider-promotion-design.md`

## Global Constraints

- Work only in `/Users/ktome1995/Program/dotfiles/.worktrees/nix-darwin-provider-promotion` on `codex/nix-darwin-provider-promotion`.
- Preserve the original checkout's uncommitted `flake.lock`; reproduce only its JSON change in the worktree.
- The 13 scoped Darwin providers must end as `provider = "nix"`.
- `WithOllama`, `WithDocker`, and `WithHermes` remain opt-in. The default profile must omit Ollama, Docker Desktop, Chrome, and Discord.
- Never select `pkgs.dia` or `pkgs.orca` for Dia Browser or Stably Orca.
- Never patch vendor-signed app bundle contents. Custom app derivations use `dontFixup = true`.
- Do not put Ollama models, Docker VM data, credentials, or application state in the Nix store.
- Never run `brew uninstall --zap`; remove a legacy package only after its Nix result passes acceptance.
- Give each scoped package migration its own commit. Push and create one Pull Request only after all tasks pass.
- `nix flake check --no-build --impure --all-systems` has one accepted baseline failure in `bootstrap-nixos-vm`: missing `users.users.nixos.isNormalUser` and `users.users.nixos.group`. No new failure is allowed.
- Use `task commit -- "message"` after Task 1 makes the Taskfile worktree-aware.

---

### Task 1: Make Taskfile commands worktree-aware

**Files:**

- Modify: `Taskfile.yml:4-9`
- Modify: `tests/bash/taskfile_test_routing.bats`

**Interfaces:**

- Consumes: Go Task `.ROOT_DIR` and `OS`.
- Produces: `DOTFILES_PATH`, equal to `.ROOT_DIR` on Darwin/Linux and `~/.dotfiles` on Windows.

- [ ] **Step 1: Add a failing routing test**

Append:

```bash
@test "quality and commit tasks target the active root on Unix" {
	command -v task >/dev/null 2>&1 || skip "task is not available"
	run task --dir "$REPO_ROOT" --dry commit -- "test commit"
	[ "$status" -eq 0 ]
	[[ "$output" == *"cd $REPO_ROOT && nix fmt"* ]]
	[[ "$output" == *"cd $REPO_ROOT && pre-commit run --all-files"* ]]
	[[ "$output" == *"cd $REPO_ROOT && git add -A"* ]]
	[[ "$output" != *'cd ~/.dotfiles'* ]]
}
```

- [ ] **Step 2: Prove the current fixed path fails**

Run `bats tests/bash/taskfile_test_routing.bats`.

Expected: the new test fails because dry-run output contains `cd ~/.dotfiles`.

- [ ] **Step 3: Resolve the active root per OS**

Replace the root variable with:

```yaml
vars:
  DISTRO: NixOS
  DOTFILES_PATH: '{{if eq OS "windows"}}~/.dotfiles{{else}}{{.ROOT_DIR}}{{end}}'
```

Keep all other global variables unchanged.

- [ ] **Step 4: Verify and commit**

Run:

```bash
bats tests/bash/taskfile_test_routing.bats
nix fmt
pre-commit run --all-files
git add Taskfile.yml tests/bash/taskfile_test_routing.bats
git commit -m "fix(task): target the active worktree"
```

Expected: tests pass and dry-run paths point at the feature worktree. This first commit uses direct Git because it fixes the unsafe `task commit` path.

### Task 2: Import the approved flake input update

**Files:**

- Modify: `flake.lock`

**Interfaces:**

- Consumes: the original checkout's uncommitted lock diff.
- Produces: nixpkgs revision `56c02bc00adcf003215cc4bd996d6efaf4cff188` in the worktree.

- [ ] **Step 1: Record source and destination revisions**

Run:

```bash
jq -r '.nodes.nixpkgs.locked.rev' /Users/ktome1995/Program/dotfiles/flake.lock
jq -r '.nodes.nixpkgs.locked.rev' flake.lock
```

Expected: source is `56c02bc00adcf003215cc4bd996d6efaf4cff188`; destination is older.

- [ ] **Step 2: Reproduce only the lock JSON change**

Read `git diff -- flake.lock` in the original checkout and apply that exact JSON patch to the worktree with `apply_patch`. Do not copy or stage any other original-checkout file.

- [ ] **Step 3: Evaluate the nine upstream Darwin attrs**

Run:

```bash
nix eval --impure --json --expr '
  let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.aarch64-darwin;
  in builtins.mapAttrs (_: x: x.version) {
    inherit (p) chatgpt discord ollama raycast tart vscode wezterm;
    google-chrome = p.google-chrome;
    onepassword = p._1password-gui;
  }
'
```

Expected: nine non-empty versions and no missing attr.

- [ ] **Step 4: Commit**

Run `task commit -- "chore(nix): update flake inputs for Darwin packages"`.

### Task 3: Enforce provider-aware and feature-aware resolution

**Files:**

- Modify: `nix/packages/sets.nix:680-920`
- Modify: `nix/packages/support-report.nix`
- Modify: `nix/home/common.nix:1-50`
- Modify: `nix/hosts/darwin/default.nix:1-175`
- Modify: `nix/flakes/packages.nix`
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`
- Modify: `scripts/powershell/tests/PackageCatalog.Tests.ps1`

**Interfaces:**

- Consumes: `support.<platform>.provider`, `source`, `nixAttr`, `identity`, and optional `installFeature`.
- Produces: `resolveForInstallFeatures`, `allWithoutForInstallFeatures`, `darwinPackages`, and empty `providerErrors` for a valid catalog.

- [ ] **Step 1: Add failing provider and profile contracts**

Add a Bats evaluation that obtains `home.packages` for the default Darwin profile and uses `jq` to require that `ollama`, `docker-desktop`, `google-chrome`, and `discord` are absent. Add source-text contracts for these exact diagnostics:

```text
provider and unsupported cannot coexist
nix provider requires a derivation
homebrew-cask provider requires cask
source = nixpkgs requires nixAttr
```

Add equivalent PowerShell contracts for `resolveForInstallFeatures`, `source`, `nixAttr`, and `identity`.

- [ ] **Step 2: Run tests and verify the new contracts fail**

```bash
bats tests/bash/package_catalog.bats tests/bash/macos_config.bats
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: Implement platform/provider/feature resolution**

Add:

```nix
  platformKey =
    if pkgs.stdenv.hostPlatform.isDarwin then "darwin"
    else if pkgs.stdenv.hostPlatform.isLinux then "linux"
    else "windows";

  featureEnabled = enabledFeatures: entry:
    !(entry ? installFeature)
    || entry.installFeature == null
    || enabledFeatures == null
    || builtins.elem entry.installFeature enabledFeatures;

  resolveForInstallFeatures =
    enabledFeatures: names:
    builtins.filter (package: package != null) (
      map (
        name:
        let
          entry = catalog.${name};
          package = entry.pkg or null;
          provider = entry.support.${platformKey}.provider or null;
        in
        if provider == "nix"
          && featureEnabled enabledFeatures entry
          && package != null
          && supports package pkgs.stdenv.hostPlatform.system
        then package
        else null
      ) names
    );

  resolve = resolveForInstallFeatures null;
```

Export `allForInstallFeatures`, `allWithoutForInstallFeatures`, and a `darwinPackages` attrset keyed by catalog ID.

- [ ] **Step 4: Pass Darwin install features into Home Manager**

Add `installFeatures ? null` to `nix/home/common.nix`. Darwin uses `sets.allWithoutForInstallFeatures installFeatures [ ]`; Linux/WSL retain the existing exclusions and `allWithout`. Pass `installFeatures` through `home-manager.extraSpecialArgs` in `nix/hosts/darwin/default.nix`.

- [ ] **Step 5: Add semantic provider errors**

Extend `providerErrors` to reject provider/unsupported coexistence, missing provider-specific fields, Nix null/non-derivation/platform mismatch, missing source/identity, missing nixpkgs attr name, and a catalog ID appearing in both Nix and Homebrew resolution. Prefix each error with `<catalog-id>: <platform>:`.

- [ ] **Step 6: Expose individual Darwin outputs**

On Darwin, merge `unfreeSets.darwinPackages` into `nix/flakes/packages.nix` with `darwin-` prefixes, producing outputs such as `.#darwin-vscode` and `.#darwin-docker-desktop`.

- [ ] **Step 7: Verify and commit**

```bash
bats tests/bash/package_catalog.bats tests/bash/macos_config.bats
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -Output Detailed"
nix build .#package-support-report --no-link
task commit -- "feat(nix): enforce Darwin provider selection"
```

### Task 4: Add Darwin verification and legacy migration adapters

**Files:**

- Create: `scripts/sh/verify-darwin-package.sh`
- Create: `scripts/sh/migrate-darwin-provider.sh`
- Create: `tests/bash/darwin_package_verification.bats`
- Modify: `scripts/sh/install-macos.sh`
- Modify: `tests/bash/install_macos.bats`
- Modify: `taskfiles/nix/taskfile.yml`
- Modify: `nix/packages/sets.nix`

**Interfaces:**

- Consumes: `support.json`, catalog ID, realized store path, enabled features, and injectable command paths.
- Produces: `task darwin:verify -- <args>` and `task darwin:migrate -- <args>`; no Homebrew removal before verification.

- [ ] **Step 1: Write failing adapter tests**

Using fake command binaries and a command log, add six complete Bats cases:

1. mismatched bundle ID exits before codesign;
2. valid app runs PlistBuddy, codesign, spctl, and exact-path open in order;
3. command identity runs the declared version arguments;
4. verification failure leaves the legacy cask installed;
5. success runs `brew uninstall --cask <token>` without `--zap`;
6. disabled install features skip both build and removal.

- [ ] **Step 2: Run tests and verify missing adapters fail**

Run `bats tests/bash/darwin_package_verification.bats tests/bash/install_macos.bats`.

- [ ] **Step 3: Implement verification CLI**

Use this interface:

```text
verify-darwin-package.sh --support-json FILE --id ID --store-path PATH [--launch]
```

For apps, read `appName`, `bundleId`, and `executable` with `jq`; inspect `PATH/Applications/<appName>/Contents/Info.plist`; require exact `CFBundleIdentifier` and `CFBundleExecutable`; run:

```bash
/usr/bin/codesign --verify --deep --strict "$app"
/usr/sbin/spctl --assess --type execute "$app"
```

For commands, execute `<store-path>/bin/<command>` with declared `versionArgs`. `--launch` opens the exact Nix app path.

- [ ] **Step 4: Implement migration CLI**

Use `--id ID` or `--all`. Evaluate/build `package-support-report`, realize `.#darwin-<id>`, call the verifier, and only then execute `legacyDarwin`. Accept only `homebrew-cask` and `homebrew-formula`; reject every other value. Never add `--zap`.

Migrated entries declare:

```nix
legacyDarwin = {
  provider = "homebrew-cask";
  name = "visual-studio-code";
};
```

Extend `supportReport` with each entry's `installFeature` and `legacyDarwin` values so the adapter reads evaluated JSON instead of parsing Nix source. The adapter filters `installFeature` against enabled feature arguments. `install-macos.sh` calls `--all` after `apply_darwin_system` and before chezmoi/runtime setup.

- [ ] **Step 5: Add Taskfile entrypoints**

```yaml
darwin:verify:
  cmds:
    - "bash scripts/sh/verify-darwin-package.sh {{.CLI_ARGS}}"
darwin:migrate:
  cmds:
    - "bash scripts/sh/migrate-darwin-provider.sh {{.CLI_ARGS}}"
```

- [ ] **Step 6: Verify and commit**

```bash
bats tests/bash/darwin_package_verification.bats tests/bash/install_macos.bats
bash -n scripts/sh/verify-darwin-package.sh scripts/sh/migrate-darwin-provider.sh
shellcheck scripts/sh/verify-darwin-package.sh scripts/sh/migrate-darwin-provider.sh
task commit -- "feat(macos): verify Nix apps before provider migration"
```

### Task 5: Migrate Visual Studio Code

**Files:**

- Modify: `nix/packages/sets.nix` (`vscode`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs.vscode` and Task 4 verifier.
- Produces: `.#darwin-vscode`, bundle `com.microsoft.VSCode`, legacy cask `visual-studio-code`.

- [ ] **Step 1: Change the test contract first**

Require `pkg = pkgs.vscode`, Darwin provider/source/attr `nix`/`nixpkgs`/`vscode`, and reject `useVSCodeRipgrep`, `postPatch`, and `cask = "visual-studio-code"`.

- [ ] **Step 2: Run focused tests and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats`.

- [ ] **Step 3: Replace the signature-breaking override**

Use:

```nix
support.darwin = {
  provider = "nix";
  source = "nixpkgs";
  nixAttr = "vscode";
  identity = {
    homepage = "https://code.visualstudio.com/";
    appName = "Visual Studio Code.app";
    bundleId = "com.microsoft.VSCode";
    executable = "Code";
  };
};
legacyDarwin = { provider = "homebrew-cask"; name = "visual-studio-code"; };
```

- [ ] **Step 4: Build and verify**

Build `.#darwin-vscode`; run Task 4 verification against its store path. Require codesign and Gatekeeper success.

- [ ] **Step 5: Apply and migrate**

Switch nix-darwin with the default profile, run `code --version`, launch `/Applications/Nix Apps/Visual Studio Code.app`, migrate `vscode`, and require `brew list --cask visual-studio-code` to fail.

- [ ] **Step 6: Commit**

Run `task commit -- "feat(macos): manage Visual Studio Code with Nix"`.

### Task 6: Migrate ChatGPT

**Files:**

- Modify: `nix/packages/sets.nix` (`chatgpt`)
- Modify: `tests/bash/package_catalog.bats`

**Interfaces:**

- Consumes: `pkgs.chatgpt` on Darwin and `./chatgpt` on Linux.
- Produces: `.#darwin-chatgpt`, bundle `com.openai.codex`, legacy cask `chatgpt`.

- [ ] **Step 1: Add a failing cross-platform contract**

Require Darwin `pkgs.chatgpt`, Linux `pkgs.callPackage ./chatgpt { }`, Microsoft Store ID `9NT1R1C2HH7J`, and no Darwin cask.

- [ ] **Step 2: Run `bats tests/bash/package_catalog.bats` and observe failure**

- [ ] **Step 3: Implement platform selection and identity**

Set `pkg = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.chatgpt else pkgs.callPackage ./chatgpt { };` and use:

```nix
darwin = {
  provider = "nix";
  source = "nixpkgs";
  nixAttr = "chatgpt";
  identity = {
    homepage = "https://openai.com/chatgpt/desktop/";
    appName = "ChatGPT.app";
    bundleId = "com.openai.codex";
    executable = "ChatGPT";
  };
};
```

Declare legacy cask `chatgpt`.

- [ ] **Step 4: Build, verify, apply, and migrate**

Build `.#darwin-chatgpt`; verify and launch the exact Nix app; migrate the cask; evaluate the existing Linux derivation for x86_64-linux and aarch64-linux.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): manage ChatGPT with Nix"`.

### Task 7: Migrate Discord while preserving WithHermes

**Files:**

- Modify: `nix/packages/sets.nix` (`discord`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs.discord`, `installFeature = "WithHermes"`.
- Produces: `.#darwin-discord`, bundle `com.hnc.Discord`, legacy cask `discord`.

- [ ] **Step 1: Add failing default/Hermes profile tests**

Default Darwin Home Manager packages must omit Discord; `DOTFILES_WITH_HERMES=1` must include it. Windows and Linux providers remain unchanged.

- [ ] **Step 2: Run focused Bats and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats`.

- [ ] **Step 3: Select the upstream package**

Use `pkg = pkgs.discord`, source `nixpkgs`, attr `discord`, homepage `https://discord.com/`, app `Discord.app`, bundle `com.hnc.Discord`, executable `Discord`, and legacy cask `discord`. Keep `WithHermes`.

- [ ] **Step 4: Build and verify both profiles**

Build/verify `.#darwin-discord`; evaluate default and Hermes package lists; apply with Hermes enabled; launch exact Nix app; migrate the cask; re-evaluate default omission.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): manage Discord with Nix"`.

### Task 8: Migrate Google Chrome while preserving WithHermes

**Files:**

- Modify: `nix/packages/sets.nix` (`google-chrome`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs.google-chrome`, `installFeature = "WithHermes"`.
- Produces: `.#darwin-google-chrome`, bundle `com.google.Chrome`, legacy cask `google-chrome`.

- [ ] **Step 1: Add failing profile and identity tests**

Require default omission, Hermes inclusion, provider/source/attr `nix`/`nixpkgs`/`google-chrome`, and no cask.

- [ ] **Step 2: Run focused Bats and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats`.

- [ ] **Step 3: Add identity metadata**

Keep `pkg = pkgs.google-chrome` and add homepage `https://www.google.com/chrome/`, app `Google Chrome.app`, bundle `com.google.Chrome`, executable `Google Chrome`, and legacy cask `google-chrome`.

- [ ] **Step 4: Build, verify, apply, and migrate**

Build/verify `.#darwin-google-chrome`; apply Hermes profile; launch exact Nix app; remove only the cask; confirm the existing Chrome user profile remains readable.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): manage Google Chrome with Nix"`.

### Task 9: Migrate Raycast

**Files:**

- Modify: `nix/packages/sets.nix` (`raycast`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs.raycast`.
- Produces: `.#darwin-raycast`, bundle `com.raycast.macos`, legacy cask `raycast`.

- [ ] **Step 1: Replace the cask contract with a Nix contract**

Require `pkg = pkgs.raycast`, source `nixpkgs`, attr `raycast`, app `Raycast.app`, bundle `com.raycast.macos`, executable `Raycast`, and no cask.

- [ ] **Step 2: Run focused Bats and observe failure**

- [ ] **Step 3: Implement metadata**

Use homepage `https://raycast.com/`, the identity above, and legacy cask `raycast`. Keep Windows/Linux unsupported reasons.

- [ ] **Step 4: Build, verify, apply, and migrate**

Build/verify `.#darwin-raycast`; launch exact Nix app; remove the cask; verify existing Raycast preferences and extensions load.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): manage Raycast with Nix"`.

### Task 10: Migrate Tart

**Files:**

- Modify: `nix/packages/sets.nix` (`tart`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/tart_vm_installer.bats`

**Interfaces:**

- Consumes: `pkgs.tart`.
- Produces: `.#darwin-tart`, command `tart`, legacy formula `openai/tools/tart`.

- [ ] **Step 1: Add a failing Nix-provider contract**

Require `pkg = pkgs.tart`, provider/source/attr `nix`/`nixpkgs`/`tart`, command identity `tart`, and no Darwin formula.

- [ ] **Step 2: Run package and Tart Bats and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/tart_vm_installer.bats`.

- [ ] **Step 3: Add Tart metadata**

Use homepage `https://tart.run/`, command `tart`, `versionArgs = [ "--version" ]`, and legacy formula `openai/tools/tart`. Preserve Apple Silicon-only unsupported reasons.

- [ ] **Step 4: Build and preserve VM state**

Build/verify `.#darwin-tart`; apply; run `tart list` read-only; migrate the formula; compare the pre/post listing of `~/.tart/vms`.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): manage Tart with Nix"`.

### Task 11: Migrate WezTerm and terminfo

**Files:**

- Modify: `nix/packages/sets.nix` (`wezterm`)
- Modify: `nix/home/common.nix`
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs.wezterm` and `pkgs.wezterm.terminfo`.
- Produces: `.#darwin-wezterm`, bundle `com.github.wez.wezterm`, legacy cask `wezterm@nightly`.

- [ ] **Step 1: Add failing GUI/terminfo tests**

Require Darwin `pkg = pkgs.wezterm`, no cask, exactly one GUI package, and working terminfo ownership.

- [ ] **Step 2: Run focused Bats and observe failure**

- [ ] **Step 3: Switch the provider**

Use source `nixpkgs`, attr `wezterm`, homepage `https://wezterm.org/`, app `WezTerm.app`, bundle `com.github.wez.wezterm`, executable `wezterm-gui`, and legacy cask `wezterm@nightly`. Remove the Darwin-null package conditional.

- [ ] **Step 4: Consolidate terminfo**

Evaluate Home Manager packages. Keep `pkgs.wezterm.terminfo` only if the selected package does not already propagate it; assert one GUI package and a resolvable `wezterm` terminfo entry.

- [ ] **Step 5: Build and perform terminal acceptance**

Build/verify, apply, launch exact app, run `wezterm --version`, `infocmp wezterm`, and `wezterm show-keys --lua`; migrate `wezterm@nightly` without deleting config.

- [ ] **Step 6: Commit**

Run `task commit -- "feat(macos): manage WezTerm with Nix"`.

### Task 12: Migrate 1Password GUI

**Files:**

- Modify: `nix/packages/sets.nix` (`_1password-gui`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `pkgs._1password-gui` and existing `_1password-cli`.
- Produces: `.#darwin-_1password-gui`, bundle `com.1password.1password`, legacy cask `1password`.

- [ ] **Step 1: Add failing GUI/CLI provider tests**

Require the GUI to be Nix-managed, retain the CLI package, and select only one `1Password.app` provider.

- [ ] **Step 2: Run focused Bats and observe failure**

- [ ] **Step 3: Add identity metadata**

Use source `nixpkgs`, attr `_1password-gui`, homepage `https://1password.com/`, app `1Password.app`, bundle `com.1password.1password`, executable `1Password`, and legacy cask `1password`.

- [ ] **Step 4: Build and probe integration without secrets**

Build/verify, apply, launch exact app, and use a metadata-only `op account list` exit-status probe. Do not call `op read` or print account details.

- [ ] **Step 5: Migrate and recheck**

Remove cask only after the probe succeeds; relaunch the Nix app and repeat the metadata-only probe. Restore the cask provider before continuing if integration fails.

- [ ] **Step 6: Commit**

Run `task commit -- "feat(macos): manage 1Password with Nix"`.

### Task 13: Replace Ollama.app with a nix-darwin service

**Files:**

- Modify: `nix/packages/sets.nix` (`ollama`)
- Modify: `nix/hosts/darwin/default.nix`
- Modify: `scripts/sh/install-macos.sh`
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`
- Modify: `tests/bash/install_macos.bats`

**Interfaces:**

- Consumes: `pkgs.ollama`, `WithOllama`, user home.
- Produces: launchd agent `com.dotfiles.ollama`, API port 11434, legacy cask `ollama-app`.

- [ ] **Step 1: Add failing service/profile tests**

Default profile must omit package and agent; `DOTFILES_WITH_OLLAMA=1` must include both; installer must not contain `OLLAMA_APP` or `open -a Ollama`.

- [ ] **Step 2: Run focused Bats and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats tests/bash/install_macos.bats`.

- [ ] **Step 3: Switch catalog to `pkgs.ollama`**

Use provider/source/attr `nix`/`nixpkgs`/`ollama`, command `ollama`, version args `[ "--version" ]`, `WithOllama`, and legacy cask `ollama-app`.

- [ ] **Step 4: Add launchd management**

Define a user agent only when `withOllama` is true. Its `ProgramArguments` are `[ "${lib.getExe pkgs.ollama}" "serve" ]`, `RunAtLoad = true`, `KeepAlive = true`, `HOME = home`, and logs live under `${home}/Library/Logs/Ollama/`.

- [ ] **Step 5: Replace GUI readiness logic**

Delete GUI path/open code. If `/api/tags` is not ready, kickstart `gui/$(id -u)/com.dotfiles.ollama` and reuse the existing bounded waiter.

- [ ] **Step 6: Build, apply, and verify state**

Build `.#darwin-ollama`; apply with `--with-ollama`; verify launchctl, `ollama --version`, and `/api/tags`; migrate the cask; compare `~/.ollama/models` before/after.

- [ ] **Step 7: Commit**

Run `task commit -- "feat(macos): run Ollama from nix-darwin"`.

### Task 14: Package and migrate Hammerspoon

**Files:**

- Create: `nix/packages/hammerspoon/default.nix`
- Modify: `nix/packages/sets.nix` (`hammerspoon`)
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: official Hammerspoon release ZIP.
- Produces: `.#darwin-hammerspoon`, bundle `org.hammerspoon.Hammerspoon`, command `hs`, legacy cask `hammerspoon`.

- [ ] **Step 1: Add a failing custom-package contract**

Require a repository derivation, source `custom`, no `nixAttr`, version `1.1.1`, official GitHub URL, `dontFixup = true`, and an `hs` binary.

- [ ] **Step 2: Run focused Bats and observe failure**

- [ ] **Step 3: Create the derivation**

Use:

```nix
version = "1.1.1";
src = fetchurl {
  url = "https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip";
  hash = "sha256-EbsckPr1Qn83x71P5+q5d0rkPh1csCDFswiNrDKEnvo=";
};
```

Unpack with `unzip`; copy `Hammerspoon.app` unchanged to `$out/Applications`; symlink `Contents/Frameworks/hs/hs` to `$out/bin/hs`; set `dontFixup = true`, unfree license, Darwin platforms, homepage `https://www.hammerspoon.org/`, and mainProgram `hs`.

- [ ] **Step 4: Wire catalog identity**

On Darwin call the custom derivation. Use app `Hammerspoon.app`, bundle `org.hammerspoon.Hammerspoon`, executable `Hammerspoon`, and legacy cask `hammerspoon`; retain other-platform unsupported reasons.

- [ ] **Step 5: Build, apply, and migrate**

Build/verify `.#darwin-hammerspoon`; apply; launch exact app; confirm existing `~/.hammerspoon/init.lua` loads; run `hs -c 'return true'`; migrate the cask.

- [ ] **Step 6: Commit**

Run `task commit -- "feat(macos): package Hammerspoon with Nix"`.

### Task 15: Package and migrate Dia Browser

**Files:**

- Create: `nix/packages/dia-browser/default.nix`
- Modify: `nix/packages/sets.nix` (`dia-browser`)
- Modify: `tests/bash/package_catalog.bats`

**Interfaces:**

- Consumes: official Dia release ZIP.
- Produces: `.#darwin-dia-browser`, bundle `company.thebrowser.dia`, legacy cask `thebrowsercompany-dia`.

- [ ] **Step 1: Add a failing product-identity test**

Require custom `dia-browser`, bundle `company.thebrowser.dia`, official Dia homepage, and an explicit rejection of `pkgs.dia`.

- [ ] **Step 2: Run `bats tests/bash/package_catalog.bats` and observe failure**

- [ ] **Step 3: Create the fixed derivation**

```nix
version = "1.45.2-85817";
src = fetchurl {
  url = "https://releases.diabrowser.com/release/Dia-1.45.2-85817.zip";
  hash = "sha256-xlbeV+uT2qS4mI6Of+1wHC9VEXqT0qssyaQ49nL/TBI=";
};
```

Unpack with `unzip`; copy `Dia.app` unchanged; set `dontFixup = true`, unfree license, `aarch64-darwin`, homepage `https://www.diabrowser.com/`, and mainProgram `Dia`.

- [ ] **Step 4: Wire, build, apply, and migrate**

Use source `custom`, app `Dia.app`, bundle `company.thebrowser.dia`, executable `Dia`, and legacy cask `thebrowsercompany-dia`. Build/verify; apply; launch exact app; confirm existing profile; migrate only the cask.

- [ ] **Step 5: Commit**

Run `task commit -- "feat(macos): package Dia Browser with Nix"`.

### Task 16: Package and migrate Stably Orca

**Files:**

- Create: `nix/packages/orca-editor/default.nix`
- Modify: `nix/packages/sets.nix` (`orca-editor`)
- Modify: `tests/bash/package_catalog.bats`

**Interfaces:**

- Consumes: official Stably Orca arm64 DMG.
- Produces: `.#darwin-orca-editor`, bundle `com.stablyai.orca`, command `orca`, legacy cask `stablyai/orca/orca`.

- [ ] **Step 1: Add a failing product-identity test**

Require custom `orca-editor`, homepage `https://onorca.dev/`, bundle `com.stablyai.orca`, and an explicit rejection of `pkgs.orca`.

- [ ] **Step 2: Run `bats tests/bash/package_catalog.bats` and observe failure**

- [ ] **Step 3: Create the derivation**

```nix
version = "1.4.188";
src = fetchurl {
  url = "https://github.com/stablyai/orca/releases/download/v1.4.188/orca-macos-arm64.dmg";
  hash = "sha256-rC7OdVj2/YkxNcUC6EshYfHGJD2KYuL7lL7G62s7JX4=";
};
```

Unpack with `undmg`; copy `Orca.app` unchanged; symlink `Contents/Resources/bin/orca` into `$out/bin`; set `dontFixup = true`, unfree license, and `aarch64-darwin`.

- [ ] **Step 4: Wire catalog identity**

Use source `custom`, app `Orca.app`, bundle `com.stablyai.orca`, executable `Orca`, and legacy cask `stablyai/orca/orca`. Preserve the Windows Winget ID.

- [ ] **Step 5: Build and migrate without losing active work**

Build and statically verify first. Ensure the current Homebrew Orca process owns no task needed for this migration; launch exact Nix app; run bundled `orca status`; migrate without `--zap`; confirm `~/.orca` and workspace state remain.

- [ ] **Step 6: Commit**

Run `task commit -- "feat(macos): package Stably Orca with Nix"`.

### Task 17: Package and migrate Docker Desktop

**Files:**

- Create: `nix/packages/docker-desktop/default.nix`
- Modify: `nix/packages/sets.nix` (`docker-desktop`)
- Modify: `nix/hosts/darwin/default.nix`
- Modify: `nix/home/common.nix`
- Modify: `scripts/sh/install-macos.sh`
- Modify: `tests/bash/package_catalog.bats`
- Modify: `tests/bash/macos_config.bats`
- Modify: `tests/bash/install_macos.bats`

**Interfaces:**

- Consumes: official Docker Desktop arm64 DMG, `WithDocker`, explicit license setting.
- Produces: `.#darwin-docker-desktop`, bundle `com.docker.docker`, Docker CLI/plugins, privileged helper convergence, legacy cask `docker-desktop`.

- [ ] **Step 1: Add failing package, license, and profile tests**

Require default omission, Docker-profile inclusion, source `custom`, fixed official URL/hash, explicit `DOTFILES_ACCEPT_DOCKER_LICENSE=1`, installer path from the Nix result, and no cask.

- [ ] **Step 2: Run focused tests and observe failure**

Run `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats tests/bash/install_macos.bats`.

- [ ] **Step 3: Create the derivation**

```nix
version = "4.88.1-237512";
src = fetchurl {
  url = "https://desktop.docker.com/mac/main/arm64/237512/Docker.dmg";
  hash = "sha256-lBAtT+BWvzpP3jddaTqulqQpFX2tA0WvmFPXFX1r1b0=";
};
```

Unpack with `undmg`; copy `Docker.app` unchanged; expose `docker`, credential helpers, and `docker-compose` through `$out/bin` and `$out/libexec/docker/cli-plugins`; set `dontFixup = true`, unfree license, and `aarch64-darwin`.

- [ ] **Step 4: Wire catalog and optional profile**

Use source `custom`, app `Docker.app`, bundle `com.docker.docker`, executable `com.docker.backend`, `WithDocker`, and legacy cask `docker-desktop`. Preserve Windows Winget and Linux system-manager providers.

- [ ] **Step 5: Bind activation to the Nix store app**

Use `${dockerDesktop}/Applications/Docker.app/Contents/MacOS/install` for privileged setup and `/Applications/Nix Apps/Docker.app` for launch. Require `DOTFILES_ACCEPT_DOCKER_LICENSE=1` before adding `--accept-license`; otherwise fail with a message that names the required setting.

- [ ] **Step 6: Preserve bounded runtime convergence**

Keep the md5 compatibility check, `docker desktop start --timeout 120`, bounded `docker info` polling, and `docker compose version`. Remove `/Applications/Docker.app/Contents/Resources/bin` from Home Manager PATH.

- [ ] **Step 7: Build and perform full acceptance**

Build/verify; apply with Docker and license flags; run vendor privileged setup; launch exact Nix app; require `docker info` and `docker compose version`; migrate the cask; confirm Docker VM/user data remain.

- [ ] **Step 8: Commit**

Run `task commit -- "feat(macos): package Docker Desktop with Nix"`.

### Task 18: Automate version updates and provider promotion PRs

**Files:**

- Create: `nix/packages/darwin-provider-candidates.nix`
- Create: `scripts/python/update_darwin_packages.py`
- Create: `tests/python/test_update_darwin_packages.py`
- Create: `.github/workflows/update-darwin-packages.yml`
- Modify: `.github/workflows/ci-consistency.yml`
- Modify: `ci/path-routing.json`
- Modify: `tests/bash/ci_routing.bats`
- Modify: `tests/python/test_ci_workflow_routing.py`
- Modify: `taskfiles/nix/taskfile.yml`

**Interfaces:**

- Consumes: `support.json`, explicit source/candidate registry, official release feeds, and `flake.lock`.
- Produces: `selectDarwinPackage`, `darwin-package-update.json`, changed-package matrix, and an unmerged `automation/darwin-packages-*` Pull Request.

- [ ] **Step 1: Write failing updater unit tests**

Using `unittest`, frozen dataclasses, `pathlib.Path`, injected HTTP/Nix runners, and temporary directories, implement these complete scenarios:

1. candidate registry never contains `dia` or `orca`;
2. only explicit attrs are evaluated;
3. build or identity failure retains custom source and emits a reason;
4. a custom update may change only version, URL, and hash literals;
5. an empty update leaves every tracked file byte-identical.

Run `python -m unittest tests.python.test_update_darwin_packages -v`; expected failure is missing module/import.

- [ ] **Step 2: Add explicit candidate registry**

```nix
{
  dia-browser = { source = "custom"; nixAttr = null; candidates = [ "dia-browser" ]; };
  orca-editor = { source = "custom"; nixAttr = null; candidates = [ "orca-editor" ]; };
  hammerspoon = { source = "custom"; nixAttr = null; candidates = [ "hammerspoon" ]; };
  docker-desktop = { source = "custom"; nixAttr = null; candidates = [ "docker-desktop" ]; };
}
```

Import this registry in `sets.nix`. Add `selectDarwinPackage = name: customPackage:` which returns the custom derivation when `source == "custom"`, and `builtins.getAttr nixAttr pkgs` when `source == "nixpkgs"`. The four catalog entries obtain `pkg`, `source`, and `nixAttr` from the same registry record, so promotion changes one mapping instead of three independent fields.

- [ ] **Step 3: Implement typed release profiles**

`update_darwin_packages.py` supports `--check`, `--write`, `--package ID`, and `--output FILE`. Use these feeds:

```text
Dia: https://releases.diabrowser.com/BoostBrowser-updates.xml
Hammerspoon: https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest
Orca: https://api.github.com/repos/stablyai/orca/releases/latest
Docker Desktop: https://desktop.docker.com/mac/main/arm64/appcast.json
```

Select stable arm64 assets; prefetch with `nix store prefetch-file --json`; build and validate identity; edit only the selected derivation's `version`, `url`, and `hash` literals.

- [ ] **Step 4: Implement provider promotion checks**

For each explicit candidate, evaluate it in updated aarch64-darwin nixpkgs, require matching homepage and identity, build it, and run Task 4 verifier. After success, update only that registry record to `source = "nixpkgs"` and the verified `nixAttr`; retain the custom derivation as a rollback implementation and emit a source-change record. On failure, leave both registry and `sets.nix` byte-identical.

- [ ] **Step 5: Add Taskfile commands**

```yaml
darwin:update:check:
  cmds:
    - python3 scripts/python/update_darwin_packages.py --check --output darwin-package-update.json
darwin:update:
  cmds:
    - python3 scripts/python/update_darwin_packages.py --write --output darwin-package-update.json
```

- [ ] **Step 6: Add Apple Silicon CI and proposal jobs**

Use `runs-on: macos-26`, pinned checkout/install-nix actions, `persist-credentials: false`, and read-only permissions for PR validation. A separate scheduled/manual job gets only `contents: write` and `pull-requests: write`, updates `flake.lock`, runs `task darwin:update`, builds the changed matrix, and creates a branch/PR with `gh pr create`. No diff is a successful no-op. Never use `pull_request_target` or auto-merge.

- [ ] **Step 7: Route and contract-test the workflow**

Path routing must enable Darwin, Nix, contract, and package-catalog checks for the registry, updater, package definitions, and workflow. Contract tests require pinned actions, `macos-26`, minimal permissions, no unpinned actions, no `pull_request_target`, and an always-running lightweight completion job.

- [ ] **Step 8: Verify and commit**

```bash
python -m unittest tests.python.test_update_darwin_packages tests.python.test_ci_workflow_routing -v
bats tests/bash/ci_routing.bats
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/*.yml
task darwin:update:check
task commit -- "feat(ci): automate Darwin provider promotion"
```

### Task 19: Validate everything and publish one PR

**Files:**

- Modify only when a validation failure identifies a scoped defect.

**Interfaces:**

- Consumes: all previous commits and acceptance evidence.
- Produces: one pushed branch and one Pull Request into `main`.

- [ ] **Step 1: Review diff and commit boundaries**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
```

Expected: clean worktree; design and plan commits; infrastructure commits; one commit per package.

- [ ] **Step 2: Run repository validation**

```bash
nix fmt -- --fail-on-change
pre-commit run --all-files
bats --print-output-on-failure tests/bash/package_catalog.bats tests/bash/macos_config.bats tests/bash/install_macos.bats tests/bash/darwin_package_verification.bats tests/bash/ci_routing.bats
python -m unittest discover -s tests/python -v
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -Output Detailed"
nix build .#package-support-report --no-link
nix flake check --no-build --impure --all-systems
```

Accept only the documented `bootstrap-nixos-vm` assertion as baseline.

- [ ] **Step 3: Build and verify all 13 outputs**

Build every `.#darwin-<catalog-id>` on Apple Silicon and run Task 4 verifier. Evaluate default, Ollama, Docker, and Hermes profiles; assert exact optional package sets and no scoped Homebrew providers.

- [ ] **Step 4: Audit live state**

For all 13 IDs, record Nix store/app/command evidence, ensure the legacy cask/formula is absent, and verify user state remains. Re-run Ollama API, Docker daemon, 1Password metadata-only integration, Tart VM list, WezTerm terminfo, and GUI launch checks.

- [ ] **Step 5: Push and create one Pull Request**

```bash
task push
gh pr create --base main --head codex/nix-darwin-provider-promotion \
  --title "feat: manage Darwin applications with Nix" \
  --body-file /tmp/nix-darwin-provider-promotion-pr.md
```

The PR body summarizes 13 migrations, optional profiles, assertions, custom provenance, live evidence, update automation, and the baseline NixOS failure.

- [ ] **Step 6: Monitor hosted checks and review threads**

Wait for every required check, inspect every review thread, and fix only scoped failures. Do not merge unless the user separately requests merge after CI.
