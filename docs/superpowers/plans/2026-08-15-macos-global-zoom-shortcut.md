# macOS Global Zoom Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS の全アプリで `Control+Command+M` を標準の `Zoom／拡大・縮小` メニュー操作へ割り当てる。

**Architecture:** nix-darwin の `system.activationScripts` に、対象ユーザーとして `/usr/bin/defaults` を実行する独立した activation script を追加する。`NSUserKeyEquivalents` には `-dict-add` で英語・日本語のメニュー名を登録し、既存の他のメニューショートカットを保持する。Bats のmacOS構成契約テストで宣言内容を検証し、既存のキーバインド文書へ利用上の制約を記載する。

**Tech Stack:** Nix / nix-darwin activation scripts、POSIX shell、Bats、Markdown

## Global Constraints

- 対象OSは macOS のみとする。
- `Zoom` と `拡大／縮小` の両方を `@^m` に登録する。
- `NSUserKeyEquivalents` の既存項目を保持するため `-dict-add` を使う。
- 設定は `DOTFILES_USER` のユーザーセッションで実行する。
- 対象アプリの自動再起動は行わない。
- 対象メニューを提供しないアプリの動作は保証しない。

---

### Task 1: macOS Zoom shortcut contract test

**Files:**

- Modify: `tests/bash/macos_config.bats:56-68`（既存のRaycast契約テスト付近）
- Test: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `nix/darwin/default.nix` に追加する `system.activationScripts.globalZoomShortcut.text`
- Produces: activation script がユーザー経由で英語・日本語の `NSUserKeyEquivalents` を `@^m` に設定することを検証する契約

- [ ] **Step 1: Write the failing test**

既存のRaycast契約テストの後に、次のテストを追加する。

```bash
@test "Darwin configures global Zoom shortcuts for English and Japanese menus" {
  local config="$REPO_ROOT/nix/darwin/default.nix"

  grep -qF 'activationScripts.globalZoomShortcut.text' "$config"
  grep -qF 'uid="$(id -u -- ${lib.escapeShellArg user})"' "$config"
  grep -qF 'runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"' "$config"
  grep -qF 'runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"' "$config"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bats tests/bash/macos_config.bats -f "Darwin configures global Zoom shortcuts"
```

Expected: FAIL because `globalZoomShortcut` and its `defaults` commands do not yet exist in `nix/darwin/default.nix`.

### Task 2: Add the nix-darwin activation

**Files:**

- Modify: `nix/darwin/default.nix:30-74`
- Test: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `user` from `DOTFILES_USER` and the existing nix-darwin activation-script conventions
- Produces: `system.activationScripts.globalZoomShortcut.text` that converges both menu labels to `@^m`

- [ ] **Step 1: Write minimal implementation**

Add the following attribute inside the existing `system = { ... };` block after `activationScripts.raycastHotkey`:

```nix
    activationScripts.globalZoomShortcut.text = ''
      uid="$(id -u -- ${lib.escapeShellArg user})"
      runAsUser() {
        launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} -- "$@"
      }

      runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
      runAsUser /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
    '';
```

The script must not call `killall`, reopen applications, or replace the complete `NSUserKeyEquivalents` dictionary.

- [ ] **Step 2: Run the focused test to verify it passes**

Run:

```bash
bats tests/bash/macos_config.bats -f "Darwin configures global Zoom shortcuts"
```

Expected: PASS.

- [ ] **Step 3: Run the complete macOS contract suite**

Run:

```bash
bats tests/bash/macos_config.bats
```

Expected: all tests pass, with only the existing environment-dependent skips if Nix is unavailable.

### Task 3: Document the shortcut and operational limits

**Files:**

- Modify: `docs/chezmoi/keybindings.md:15-20`
- Test: `git diff --check`

**Interfaces:**

- Consumes: the implemented `Control+Command+M` macOS activation behavior
- Produces: user-facing keybinding documentation consistent with the existing macOS auxiliary shortcuts

- [ ] **Step 1: Add the keybinding row**

Add this row to the unified-rules table:

```markdown
| `Ctrl+Command+M` (macOS) | GUI window zoom / restore | `Ctrl+Command+M` |
```

- [ ] **Step 2: Add usage constraints near the existing macOS window-manager note**

Add these bullets after the paragraph describing contract-external operations:

```markdown
- macOS の全アプリに `Ctrl+Command+M` を割り当て、標準メニューの `Zoom` または `拡大／縮小` を実行する。
- 設定反映後は対象アプリを再起動する。対象メニューを持たないアプリや、一部のElectronアプリでは動作しない場合がある。
```

- [ ] **Step 3: Run formatting validation**

Run:

```bash
git diff --check
```

Expected: no output and exit status 0.

### Task 4: Verify the final change

**Files:**

- Verify: `nix/darwin/default.nix`
- Verify: `tests/bash/macos_config.bats`
- Verify: `docs/chezmoi/keybindings.md`

- [ ] **Step 1: Review the final diff**

Run:

```bash
git diff -- nix/darwin/default.nix tests/bash/macos_config.bats docs/chezmoi/keybindings.md
git status --short
```

Confirm that only macOS activation, its contract test, and the keybinding documentation changed; do not include unrelated worktree changes.

- [ ] **Step 2: Run the relevant test routing**

Run:

```bash
task test:bash -- tests/bash/macos_config.bats
```

If the task does not accept a path argument, run the direct Bats command from Task 2 instead and record that result.

- [ ] **Step 3: Evaluate the Darwin configuration when Nix is available**

Run:

```bash
env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex \
  nix eval --impure --raw --expr '
    let
      flake = builtins.getFlake (toString ./.);
    in flake.darwinConfigurations.macos.config.system.activationScripts.globalZoomShortcut.text
  '
```

Expected: the rendered activation text contains both `defaults` commands and the `launchctl asuser` user boundary. If Nix is unavailable, report the check as skipped rather than claiming evaluation passed.
