# Unified Terminal Window Manager Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WezTerm、macOS Terminal.app、Windows Terminal、tmux、Herdr の Window Manager 操作を `Ctrl+Space` prefix と共通 suffix に統一し、全 OS で必要な依存パッケージ・設定・配備を dotfiles から管理する。

**Architecture:** tmux、Herdr、WezTerm は自身の prefix/key table で共通契約を実装する。prefix を持たない Terminal.app は Hammerspoon、Windows Terminal は AutoHotkey v2 をアプリ限定の1秒タイムアウト state machine として使い、各ターミナルのネイティブ操作へ変換する。ネスト時は `Ctrl+Space Ctrl+Space` を内側へ転送し、各ターゲットが持たない Workspace/Session 操作は握りつぶす。依存パッケージは `nix/packages/sets.nix` を SSOT とし、chezmoi の既存 terminal deploy script から設定を配備する。

**Tech Stack:** Nix flakes、chezmoi templates、WezTerm Lua、tmux、Herdr TOML、Hammerspoon Lua、AutoHotkey v2、Windows Terminal JSON、PowerShell/Pester、Bats、GitHub Actions

## Global Constraints

- 作業は `/Users/ktome1995/Program/dotfiles/.worktrees/unified-terminal-keybindings` の `feat/unified-terminal-keybindings` だけで行う。primary checkout の未コミット `flake.lock` は変更、退避、復元しない。
- `flake.lock` は更新しない。パッケージ追加は `nix/packages/sets.nix` を唯一の入力とし、生成物だけを再生成する。
- 共通 prefix は `Ctrl+Space`、prefix timeout は WezTerm、Hammerspoon、AutoHotkey で1秒とする。
- 共通 suffix は Workspace `w/a/j/k`、Tab `n/q/Tab/Shift+Tab`、Pane `h/j/k/l/v/-/x`、Session `g/d` とする。
- `Ctrl+Space Ctrl+Space suffix` は内側の tmux/Herdr に prefix を1回送る。
- Hammerspoon は `com.apple.Terminal`、AutoHotkey は `WindowsTerminal.exe` が foreground のときだけ prefix を捕捉する。
- Terminal.app が持たない Workspace、Session、上下分割、方向 pane focus は no-op にする。Windows Terminal が持たない Workspace、Session は no-op にする。
- 旧 Tab/Pane/Workspace/Session キーは削除する。エディタ操作、shell 操作、tmux の直接 `Ctrl+H/J/K/L` Neovim 境界移動など、Window Manager 契約外のキーは維持する。
- WezTerm の GUI window focus は共通 pane suffix と衝突させない。macOS は直接 `SUPER|ALT+h/l`、Windows/Linux は既存の直接 `ALT|SHIFT+h/l` を維持する。
- テストは省略しない。ローカルで実行不能な Windows 実機テストは GitHub Actions の Windows job で確認し、未実施を成功扱いしない。
- コミットは各タスク末尾に記載した `task commit DOTFILES_PATH="$PWD"` を使い、各タスクの赤テスト、実装、緑テストを同じタスク内で完了する。
- PR は required Actions と未解決 review thread を確認してから merge する。失敗中・pending・skipped の required check がある状態では merge しない。

---

### Task 1: Hammerspoon と AutoHotkey をパッケージ SSOT に追加する

**Files:**

- Modify: `tests/bash/package_catalog.bats`
- Modify: `scripts/powershell/tests/PackageCatalog.Tests.ps1`
- Modify: `nix/packages/sets.nix`
- Regenerate: `windows/winget/packages.json`

**Interfaces:**

- Consumes: `nix/packages/sets.nix` の package catalog schema と `.#winget-export`。
- Produces: Darwin の Homebrew cask `hammerspoon`、Windows の Winget package `AutoHotkey.AutoHotkey`。Linux では両 package を非対応として明示する。

- [ ] **Step 1: package provider 契約の失敗テストを書く**

`tests/bash/package_catalog.bats` に次のテストを追加する。

```bash
@test "terminal keybinding helpers have platform-scoped providers" {
  run rg -U 'hammerspoon = \{.*?category = "terminal";.*?darwin = \{.*?provider = "homebrew-cask";.*?cask = "hammerspoon";' "$REPO_ROOT/nix/packages/sets.nix"
  [ "$status" -eq 0 ]

  run rg -U 'autohotkey = \{.*?winget = "AutoHotkey\.AutoHotkey";.*?category = "terminal";.*?windows = \{.*?provider = "winget";' "$REPO_ROOT/nix/packages/sets.nix"
  [ "$status" -eq 0 ]
}
```

`scripts/powershell/tests/PackageCatalog.Tests.ps1` に次を追加する。

```powershell
It 'should generate AutoHotkey for the Windows terminal keybinding adapter' {
    $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
    $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
    $package = @($wingetSource.Packages | Where-Object PackageIdentifier -eq 'AutoHotkey.AutoHotkey')
    $package.Count | Should -Be 1
}

It 'should keep Hammerspoon out of the Windows manifest' {
    $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
    $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
    @($wingetSource.Packages | Where-Object PackageIdentifier -Match 'Hammerspoon').Count | Should -Be 0
}
```

- [ ] **Step 2: 対象テストが未実装で失敗することを確認する**

```bash
bats tests/bash/package_catalog.bats
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0
```

Expected: Hammerspoon/AutoHotkey が catalog と生成 manifest にないため FAIL。

- [ ] **Step 3: package catalog に OS scope を明示して追加する**

`nix/packages/sets.nix` の terminal category に次を追加する。

```nix
hammerspoon = {
  winget = null;
  category = "terminal";
  support = {
    darwin = {
      provider = "homebrew-cask";
      cask = "hammerspoon";
    };
    linux = {
      unsupported = "Hammerspoon is only available on macOS";
    };
    windows = {
      unsupported = "Hammerspoon is only available on macOS";
    };
  };
};
autohotkey = {
  winget = "AutoHotkey.AutoHotkey";
  category = "terminal";
  support = {
    darwin = {
      unsupported = "AutoHotkey is only available on Windows";
    };
    linux = {
      unsupported = "AutoHotkey is only available on Windows";
    };
    windows = {
      provider = "winget";
    };
  };
};
```

- [ ] **Step 4: Winget 生成物を専用一時出力から更新する**

```bash
winget_result="$(mktemp -d)/winget-export"
nix build .#winget-export -o "$winget_result"
cp "$winget_result/winget/packages.json" windows/winget/packages.json
jq empty windows/winget/packages.json
git diff --exit-code -- flake.lock
```

Expected: `windows/winget/packages.json` に `AutoHotkey.AutoHotkey` が1件追加され、`flake.lock` の差分はない。

- [ ] **Step 5: package tests と Nix 評価を通す**

```bash
bats tests/bash/package_catalog.bats
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0
nix eval .#darwinConfigurations.macos.config.homebrew.casks --json | jq -e 'index("hammerspoon") != null'
nix flake check --no-build --impure
git diff --check
```

Expected: 全て exit 0。Darwin casks に Hammerspoon、Winget manifest に AutoHotkey があり、lockfile は不変。

- [ ] **Step 6: package 変更をコミットする**

```bash
git add tests/bash/package_catalog.bats \
  scripts/powershell/tests/PackageCatalog.Tests.ps1 \
  nix/packages/sets.nix windows/winget/packages.json
task commit DOTFILES_PATH="$PWD" -- "feat: install terminal keybinding helpers"
```

Expected: package SSOT、生成 manifest、対応テストだけを含むコミットが作成される。

---

### Task 2: tmux と Herdr のネイティブ prefix 契約を統一する

**Files:**

- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `scripts/powershell/tests/chezmoi/HerdrConfig.Tests.ps1`
- Modify: `chezmoi/dot_tmux.conf`
- Modify: `chezmoi/dot_config/herdr/config.toml`
- Modify: `chezmoi/AppData/Roaming/herdr/config.toml`

**Interfaces:**

- Consumes: tmux prefix/key table、Herdr 0.8.x `[keys]` schema。
- Produces: tmux の Workspace=Session、Tab=Window mapping と、Unix/Windows で同一の Herdr key mapping。

- [ ] **Step 1: tmux と Herdr の共通契約テストを先に書く**

`Keybindings.Tests.ps1` の tmux context を、次の契約を table-driven に検証する形へ置き換える。

```powershell
$tmux | Should -Match '(?m)^set -g prefix C-Space$'
$tmux | Should -Match '(?m)^bind C-Space send-prefix$'
foreach ($binding in @(
    @{ Key = 'w'; Command = 'choose-tree -s' },
    @{ Key = 'a'; Command = 'command-prompt' },
    @{ Key = 'n'; Command = 'new-window' },
    @{ Key = 'q'; Command = 'kill-window' },
    @{ Key = 'Tab'; Command = 'next-window' },
    @{ Key = 'BTab'; Command = 'previous-window' },
    @{ Key = 'h'; Command = 'select-pane -L' },
    @{ Key = 'j'; Command = 'select-pane -D' },
    @{ Key = 'k'; Command = 'select-pane -U' },
    @{ Key = 'l'; Command = 'select-pane -R' },
    @{ Key = 'v'; Command = 'split-window -h' },
    @{ Key = '-'; Command = 'split-window -v' },
    @{ Key = 'x'; Command = 'kill-pane' },
    @{ Key = 'g'; Command = 'choose-tree -Zw' },
    @{ Key = 'd'; Command = 'detach-client' }
)) {
    $tmux | Should -Match "(?m)^bind $([regex]::Escape($binding.Key)) $([regex]::Escape($binding.Command))"
}
$tmux | Should -Not -Match '(?m)^set -g prefix C-a$'
```

同時に、既存の直接 `bind-key -n C-h/j/k/l` assertion は残す。

`HerdrConfig.Tests.ps1` に全 key-value を検証する table を追加する。

```powershell
$expected = [ordered]@{
    prefix = 'ctrl+space'
    workspace_picker = 'prefix+w'
    new_workspace = 'prefix+a'
    navigate_workspace_down = 'j'
    navigate_workspace_up = 'k'
    new_tab = 'prefix+n'
    close_tab = 'prefix+q'
    next_tab = 'prefix+tab'
    previous_tab = 'prefix+shift+tab'
    focus_pane_left = 'prefix+h'
    focus_pane_down = 'prefix+j'
    focus_pane_up = 'prefix+k'
    focus_pane_right = 'prefix+l'
    split_vertical = 'prefix+v'
    split_horizontal = 'prefix+minus'
    close_pane = 'prefix+x'
    goto = 'prefix+g'
    detach = 'prefix+d'
}
foreach ($entry in $expected.GetEnumerator()) {
    $content | Should -Match "(?m)^$($entry.Key)\s*=\s*`"$([regex]::Escape($entry.Value))`"\s*$"
}
```

- [ ] **Step 2: focused tests が旧設定で失敗することを確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/HerdrConfig.Tests.ps1 -MinimumCoverage 0
```

Expected: tmux の `C-a` と旧 tab/split keys、Herdr の `[keys]` 欠落により FAIL。

- [ ] **Step 3: tmux key table を共通 suffix へ置換する**

`chezmoi/dot_tmux.conf` の旧 prefix と Window Manager binding を次へ置き換える。

```tmux
unbind C-b
unbind C-a
set -g prefix C-Space
bind C-Space send-prefix

bind w choose-tree -s
bind a command-prompt -p "new workspace:" "new-session -s '%%'"
bind n new-window
bind q kill-window
bind Tab next-window
bind BTab previous-window

bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind v split-window -h
bind - split-window -v
bind x kill-pane

bind g choose-tree -Zw
bind d detach-client
```

既存の copy mode、reload、mouse、`bind-key -n C-h/j/k/l` は残す。旧 `bind t new-window` と旧 `bind l/h next-window/previous-window` は削除する。

- [ ] **Step 4: Herdr の両設定へ同一 `[keys]` table を追加する**

両方の `config.toml` に次を同じ順序で追加する。

```toml
[keys]
prefix = "ctrl+space"
workspace_picker = "prefix+w"
new_workspace = "prefix+a"
navigate_workspace_down = "j"
navigate_workspace_up = "k"
new_tab = "prefix+n"
close_tab = "prefix+q"
next_tab = "prefix+tab"
previous_tab = "prefix+shift+tab"
focus_pane_left = "prefix+h"
focus_pane_down = "prefix+j"
focus_pane_up = "prefix+k"
focus_pane_right = "prefix+l"
split_vertical = "prefix+v"
split_horizontal = "prefix+minus"
close_pane = "prefix+x"
goto = "prefix+g"
detach = "prefix+d"
```

- [ ] **Step 5: parser と resolved key table を検証する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/HerdrConfig.Tests.ps1 -MinimumCoverage 0
HERDR_CONFIG_PATH="$PWD/chezmoi/dot_config/herdr/config.toml" herdr config check
HERDR_CONFIG_PATH="$PWD/chezmoi/AppData/Roaming/herdr/config.toml" herdr config check
tmux_socket="dotfiles-keybindings-$$"
tmux -L "$tmux_socket" -f "$PWD/chezmoi/dot_tmux.conf" start-server
tmux -L "$tmux_socket" list-keys | rg 'C-Space|choose-tree|new-window|select-pane|split-window|detach-client'
tmux -L "$tmux_socket" kill-server
cmp chezmoi/dot_config/herdr/config.toml chezmoi/AppData/Roaming/herdr/config.toml
```

Expected: focused Pester、両 Herdr parser、tmux config load、config equality が全て PASS。tmux server は専用 socket だけを停止する。

- [ ] **Step 6: native multiplexer 変更をコミットする**

```bash
git add scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 \
  scripts/powershell/tests/chezmoi/HerdrConfig.Tests.ps1 \
  chezmoi/dot_tmux.conf chezmoi/dot_config/herdr/config.toml \
  chezmoi/AppData/Roaming/herdr/config.toml
task commit DOTFILES_PATH="$PWD" -- "feat: unify tmux and Herdr keybindings"
```

---

### Task 3: WezTerm を共通契約と nested prefix に移行する

**Files:**

- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `chezmoi/terminals/wezterm/wezterm.lua`

**Interfaces:**

- Consumes: WezTerm leader、`PromptInputLine`、`ShowLauncherArgs`、pane/tab/workspace actions。
- Produces: 全 OS 共通の Leader key table、名前付き workspace 作成、navigator、domain detach、内側への prefix 転送。

- [ ] **Step 1: WezTerm の resolved contract を表す失敗テストを書く**

`Keybindings.Tests.ps1` に次を検証する assertions を追加し、旧 Leader `t/x/h/l` tab/window bindings、Leader 数字 tab bindings、旧 OS 別 pane bindingsの不在も検証する。

```powershell
$content | Should -Match 'key = "Space", mods = "CTRL", timeout_milliseconds = 1000'
$content | Should -Match 'key = "Space", mods = "LEADER", action = act\.SendKey\(\{ key = "Space", mods = "CTRL" \}\)'
$content | Should -Match 'key = "w", mods = "LEADER", action = act\.ShowLauncherArgs\(\{ flags = "FUZZY\|WORKSPACES" \}\)'
$content | Should -Match 'key = "a", mods = "LEADER", action = act\.PromptInputLine'
$content | Should -Match 'key = "n", mods = "LEADER", action = act\.SpawnTab\("CurrentPaneDomain"\)'
$content | Should -Match 'key = "q", mods = "LEADER", action = act\.CloseCurrentTab'
$content | Should -Match 'key = "Tab", mods = "LEADER", action = act\.ActivateTabRelative\(1\)'
$content | Should -Match 'key = "Tab", mods = "LEADER\|SHIFT", action = act\.ActivateTabRelative\(-1\)'
$content | Should -Match 'key = "h", mods = "LEADER", action = act\.ActivatePaneDirection\("Left"\)'
$content | Should -Match 'key = "j", mods = "LEADER", action = act\.ActivatePaneDirection\("Down"\)'
$content | Should -Match 'key = "k", mods = "LEADER", action = act\.ActivatePaneDirection\("Up"\)'
$content | Should -Match 'key = "l", mods = "LEADER", action = act\.ActivatePaneDirection\("Right"\)'
$content | Should -Match 'key = "v", mods = "LEADER", action = act\.SplitHorizontal'
$content | Should -Match 'key = "-", mods = "LEADER", action = act\.SplitVertical'
$content | Should -Match 'key = "x", mods = "LEADER", action = act\.CloseCurrentPane'
$content | Should -Match 'flags = "FUZZY\|WORKSPACES\|TABS\|DOMAINS"'
$content | Should -Match 'key = "d", mods = "LEADER", action = act\.DetachDomain\("CurrentPaneDomain"\)'
$content | Should -Not -Match 'mods = "LEADER", action = act\.ActivateTab\([0-8]\)'
```

- [ ] **Step 2: focused test が旧 WezTerm key table で失敗することを確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
```

Expected: timeout、workspace、tab、pane、session、nested prefix assertions が FAIL。

- [ ] **Step 3: leader と共通 key table を実装する**

`wezterm.lua` で leader timeout を1秒にし、共通 key table を次の actions で構成する。

```lua
leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 },
```

```lua
{ key = "Space", mods = "LEADER", action = act.SendKey({ key = "Space", mods = "CTRL" }) },
{ key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
{
  key = "a",
  mods = "LEADER",
  action = act.PromptInputLine({
    description = "Enter name for new workspace",
    action = wezterm.action_callback(function(window, pane, line)
      if line and line ~= "" then
        window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
      end
    end),
  }),
},
{ key = "n", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
{ key = "q", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },
{ key = "Tab", mods = "LEADER", action = act.ActivateTabRelative(1) },
{ key = "Tab", mods = "LEADER|SHIFT", action = act.ActivateTabRelative(-1) },
{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
{ key = "v", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
{ key = "g", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES|TABS|DOMAINS" }) },
{ key = "d", mods = "LEADER", action = act.DetachDomain("CurrentPaneDomain") },
```

旧 Window Manager bindings を削除する。GUI window focus は macOS の `SUPER|ALT+h/l` と Windows/Linux の既存 `ALT|SHIFT+h/l` に限定して残し、共通 Leader `h/l` と衝突させない。

- [ ] **Step 4: WezTerm parser と resolved bindings を確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
wezterm --config-file "$PWD/chezmoi/terminals/wezterm/wezterm.lua" show-keys > /tmp/dotfiles-wezterm-keys.txt
rg 'LEADER.*(SpawnTab|ActivateTabRelative|ActivatePaneDirection|SplitHorizontal|SplitVertical|CloseCurrentPane|DetachDomain)' /tmp/dotfiles-wezterm-keys.txt
if rg -q 'LEADER.*ActivateTab\([0-8]\)' /tmp/dotfiles-wezterm-keys.txt; then exit 1; fi
```

Expected: Pester と WezTerm config evaluation が PASSし、旧 numbered tab binding がない。

- [ ] **Step 5: WezTerm 変更をコミットする**

```bash
git add scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 \
  chezmoi/terminals/wezterm/wezterm.lua
task commit DOTFILES_PATH="$PWD" -- "feat: unify WezTerm window manager keys"
```

---

### Task 4: Terminal.app 用 Hammerspoon adapter を追加する

**Files:**

- Create: `chezmoi/terminals/hammerspoon/init.lua`
- Modify: `chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl`
- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1`

**Interfaces:**

- Consumes: Hammerspoon `hs.eventtap`、Terminal.app の標準 shortcuts、chezmoi Unix deploy script。
- Produces: Terminal.app 限定の `Ctrl+Space` state machine と `~/.hammerspoon/init.lua` deployment。

- [ ] **Step 1: app scope、timeout、mapping、deployment の失敗テストを書く**

`Keybindings.Tests.ps1` に次を検証する context を追加する。

```powershell
$path = Join-Path $script:chezmoiRoot 'terminals/hammerspoon/init.lua'
Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
$content = Get-Content -LiteralPath $path -Raw
$content | Should -Match 'com\.apple\.Terminal'
$content | Should -Match 'hs\.timer\.doAfter\(1'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "cmd" \}, "t"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "cmd" \}, "w"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "ctrl" \}, "tab"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "ctrl", "shift" \}, "tab"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "cmd" \}, "d"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "cmd", "shift" \}, "d"'
$content | Should -Match 'hs\.eventtap\.keyStroke\(\{ "ctrl" \}, "space"'
$content | Should -Match 'hs\.accessibilityState\(\)'
```

`ChezmoiTemplate.Tests.ps1` では Darwin render に Hammerspoon source hash と `~/.hammerspoon/init.lua` destination があり、Linux render には destination がないことを検証する。

- [ ] **Step 2: focused tests が adapter 欠落で失敗することを確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0
```

Expected: `init.lua` と deploy contract が存在しないため FAIL。

- [ ] **Step 3: Terminal.app 限定 state machine を実装する**

`init.lua` は次の構造にする。

```lua
local terminalBundleId = "com.apple.Terminal"
local prefixPending = false
local prefixTimer = nil
local forwardingPrefix = false

local function resetPrefix()
  prefixPending = false
  if prefixTimer then
    prefixTimer:stop()
    prefixTimer = nil
  end
end

local function send(mods, key)
  resetPrefix()
  hs.eventtap.keyStroke(mods, key, 0)
end

local suffixActions = {
  n = function() send({ "cmd" }, "t") end,
  q = function() send({ "cmd" }, "w") end,
  tab = function() send({ "ctrl" }, "tab") end,
  shift_tab = function() send({ "ctrl", "shift" }, "tab") end,
  v = function() send({ "cmd" }, "d") end,
  x = function() send({ "cmd", "shift" }, "d") end,
}

terminalPrefixTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  if forwardingPrefix then return false end
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= terminalBundleId then
    resetPrefix()
    return false
  end

  local key = event:getCharacters(true):lower()
  local flags = event:getFlags()
  if not prefixPending then
    if key == " " and flags.ctrl then
      prefixPending = true
      prefixTimer = hs.timer.doAfter(1, resetPrefix)
      return true
    end
    return false
  end

  if key == " " and flags.ctrl then
    resetPrefix()
    forwardingPrefix = true
    hs.eventtap.keyStroke({ "ctrl" }, "space", 0)
    hs.timer.doAfter(0, function() forwardingPrefix = false end)
    return true
  end
  local action = key == "\t" and (flags.shift and suffixActions.shift_tab or suffixActions.tab) or suffixActions[key]
  resetPrefix()
  if action then action() end
  return true
end)

hs.autoLaunch(true)
if hs.accessibilityState() then
  terminalPrefixTap:start()
else
  hs.alert.show("Hammerspoon Accessibility permission is required for Terminal keybindings")
end
```

`w/a/j/k/h/l/-/g/d` とその他の未対応 suffix は event を握りつぶして reset する。Escape も reset して握りつぶす。Hammerspoon 自身の window manager hotkeys は追加しない。

- [ ] **Step 4: Darwin のみ Hammerspoon config を配備する**

Unix deploy template の hash line に `terminals/hammerspoon/init.lua` を含め、Darwin template branch 内で次を実行する。

```bash
deploy_file "$CHEZMOI_SOURCE/terminals/hammerspoon/init.lua" "$HOME_DIR/.hammerspoon/init.lua"
```

Linux render にはこの copy を含めない。

- [ ] **Step 5: syntax、template、focused tests を通す**

```bash
luac -p chezmoi/terminals/hammerspoon/init.lua
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0
chezmoi --source "$PWD/chezmoi" execute-template \
  < chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl \
  | rg 'hammerspoon/init.lua'
```

Expected: Lua syntax、Pester、Darwin deployment contract が PASS。

- [ ] **Step 6: Terminal.app adapter をコミットする**

```bash
git add chezmoi/terminals/hammerspoon/init.lua \
  chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl \
  scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 \
  scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1
task commit DOTFILES_PATH="$PWD" -- "feat: manage Terminal app prefix keybindings"
```

---

### Task 5: Windows Terminal 用 AutoHotkey transport を追加する

**Files:**

- Create: `chezmoi/terminals/windows-terminal/terminal-keybindings.ahk`
- Modify: `chezmoi/terminals/windows-terminal/settings.json`
- Modify: `chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl`
- Create: `chezmoi/.chezmoiscripts/run_onchange_start-terminal-keybindings_windows.ps1.tmpl`
- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1`

**Interfaces:**

- Consumes: AutoHotkey v2 `InputHook`、Windows Terminal actions/keybindings、Windows Startup shortcut。
- Produces: `Ctrl+Space` suffix から `F13`–`F23` への app-scoped transport と、自動起動・再読み込み可能な managed script。

- [ ] **Step 1: transport mapping と startup lifecycle の失敗テストを書く**

`Keybindings.Tests.ps1` で次の mapping を table-driven に検証する。

```powershell
$transport = [ordered]@{
    f13 = 'User.newTab'
    f14 = 'User.closeTab'
    f15 = 'User.nextTab'
    f16 = 'User.prevTab'
    f17 = 'User.moveFocus.left'
    f18 = 'User.moveFocus.down'
    f19 = 'User.moveFocus.up'
    f20 = 'User.moveFocus.right'
    f21 = 'User.splitPane.horizontal'
    f22 = 'User.splitPane.vertical'
    f23 = 'User.closePane'
}
foreach ($entry in $transport.GetEnumerator()) {
    @($settings.keybindings | Where-Object keys -eq $entry.Key).id | Should -Be $entry.Value
}
```

また AHK source が以下を含むことを検証する。

```powershell
$ahk | Should -Match '#Requires AutoHotkey v2\.0'
$ahk | Should -Match '#HotIf WinActive\("ahk_exe WindowsTerminal\.exe"\)'
$ahk | Should -Match '\^Space::StartTerminalPrefix\(\)'
$ahk | Should -Match 'InputHook\("T1"\)'
$ahk | Should -Match 'KeyOpt\("\{All\}", "NS"\)'
$ahk | Should -Match 'A_Args\[1\] = "--check"'
$ahk | Should -Match 'SendEvent "\{Ctrl down\}\{Space\}\{Ctrl up\}"'
foreach ($key in 13..23) { $ahk | Should -Match "SendEvent `"\{F$key\}`"" }
```

`ChezmoiTemplate.Tests.ps1` では Windows deploy destination `%APPDATA%\dotfiles\terminal-keybindings.ahk`、AutoHotkey v2 executable discovery、Startup `.lnk` 作成、script launch を検証する。

- [ ] **Step 2: focused tests が transport 欠落で失敗することを確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0
```

Expected: AHK source、F13–F23、startup script がないため FAIL。

- [ ] **Step 3: AutoHotkey v2 prefix state machine を実装する**

`terminal-keybindings.ahk` は次の構造にする。

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

global TerminalInputHook := ""
global TerminalPrefixPending := false

if A_Args.Length > 0 && A_Args[1] = "--check"
    ExitApp 0

StartTerminalPrefix() {
    global TerminalInputHook, TerminalPrefixPending
    if TerminalPrefixPending {
        TerminalInputHook.Stop()
        TerminalPrefixPending := false
        SendEvent "{Ctrl down}{Space}{Ctrl up}"
        return
    }
    if IsObject(TerminalInputHook)
        TerminalInputHook.Stop()
    TerminalPrefixPending := true
    TerminalInputHook := InputHook("T1")
    TerminalInputHook.KeyOpt("{All}", "NS")
    TerminalInputHook.OnKeyDown := HandleTerminalSuffix
    TerminalInputHook.OnEnd := HandleTerminalPrefixEnd
    TerminalInputHook.Start()
}

HandleTerminalSuffix(input, vk, sc) {
    global TerminalPrefixPending
    key := StrLower(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))
    shifted := GetKeyState("Shift", "P")
    TerminalPrefixPending := false
    input.Stop()

    actions := Map(
        "n", "{F13}", "q", "{F14}",
        "tab", shifted ? "{F16}" : "{F15}",
        "h", "{F17}", "j", "{F18}", "k", "{F19}", "l", "{F20}",
        "v", "{F21}", "-", "{F22}", "x", "{F23}"
    )
    if actions.Has(key)
        SendEvent actions[key]
}

HandleTerminalPrefixEnd(*) {
    global TerminalPrefixPending
    TerminalPrefixPending := false
}

#HotIf WinActive("ahk_exe WindowsTerminal.exe")
$^Space::StartTerminalPrefix()
#HotIf
```

`w/a/g/d`、Escape、未知 suffix は1秒以内でも送信せず終了する。prefix 待機中のキーは `S` option で Windows Terminal へ漏らさない。

- [ ] **Step 4: Windows Terminal を transport keys のみに移行する**

`settings.json` に `User.closeTab` action を追加し、F13–F23 を上記 ID へ割り当てる。旧 direct Window Manager keys (`ctrl+tab`、`ctrl+shift+tab`、`ctrl+alt+t`、`ctrl+shift+w`、`alt+arrow`、`alt+shift+plus/minus`、pane swap/resize) は keybindings から削除する。copy/paste/find/font/fullscreen/zoom/Enter transport は維持する。

- [ ] **Step 5: AHK source を配備し Startup shortcut を冪等に管理する**

Windows deploy script の hash に AHK source を含め、次へ配備する。

```powershell
Deploy-File "$ChezmoiSource\terminals\windows-terminal\terminal-keybindings.ahk" `
  "$env:APPDATA\dotfiles\terminal-keybindings.ahk"
```

新しい `run_onchange_start-terminal-keybindings_windows.ps1.tmpl` は source hash を header に持ち、次の順で executable を探索する。

```powershell
$Candidates = @(
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)
$AutoHotkey = $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $AutoHotkey) { throw "AutoHotkey v2 executable was not found" }
```

`WScript.Shell.CreateShortcut()` で current user Startup に `.lnk` を作り、`TargetPath` を executable、`Arguments` を quoted managed AHK path にする。既存 AutoHotkey process を広く kill せず、`#SingleInstance Force` により同じ script を再起動する。

- [ ] **Step 6: JSON、templates、focused tests を通す**

```bash
jq empty chezmoi/terminals/windows-terminal/settings.json
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1 -MinimumCoverage 0
git diff --check
```

Windows CI ではさらに AutoHotkey v2 の executable で `/ErrorStdOut` と `--check` を使い、managed source が parse 後に exit 0 になることを確認する。

Expected: JSON parse、Pester、Windows template contract が PASS。旧 direct Window Manager keys は検出されない。

- [ ] **Step 7: Windows adapter をコミットする**

```bash
git add chezmoi/terminals/windows-terminal/terminal-keybindings.ahk \
  chezmoi/terminals/windows-terminal/settings.json \
  chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl \
  chezmoi/.chezmoiscripts/run_onchange_start-terminal-keybindings_windows.ps1.tmpl \
  scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 \
  scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1
task commit DOTFILES_PATH="$PWD" -- "feat: manage Windows Terminal prefix keybindings"
```

---

### Task 6: 共通契約ドキュメントと回帰テストを完成させる

**Files:**

- Modify: `docs/chezmoi/keybindings.md`
- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1`
- Modify: `.github/workflows/ci-chezmoi.yml`

**Interfaces:**

- Consumes: 全 adapter の実装済み key table と capability boundary。
- Produces: 1つの共通 suffix table、target capability matrix、nested prefix 手順、旧 binding 不在を保証する回帰テスト。

- [ ] **Step 1: 文書契約の失敗テストを書く**

`Keybindings.Tests.ps1` で docs が以下を明示することを検証する。

```powershell
$docs | Should -Match 'Ctrl\+Space Ctrl\+Space'
$docs | Should -Match 'Terminal\.app.*no-op'
$docs | Should -Match 'Windows Terminal.*Workspace.*非対応'
$docs | Should -Match 'Workspace.*w.*picker'
$docs | Should -Match 'Workspace.*a.*新規'
$docs | Should -Match 'Tab.*n.*新規'
$docs | Should -Match 'Tab.*q.*閉じる'
$docs | Should -Match 'Pane.*h/j/k/l'
$docs | Should -Match 'Session.*g.*navigator'
$docs | Should -Match 'Session.*d.*detach'
```

さらに旧キーの代表例を source と docs の両方で禁止する regression table を追加する。

- [ ] **Step 2: docs test が旧文書で失敗することを確認する**

```bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 -MinimumCoverage 0
```

Expected: capability matrix と nested prefix の説明不足により FAIL。

- [ ] **Step 3: keybinding 文書を新体系へ全面更新する**

`docs/chezmoi/keybindings.md` の terminal Window Manager section を以下の表へ置換する。

```markdown
| 対象      | suffix                | 操作                    |
| --------- | --------------------- | ----------------------- |
| Workspace | `w`                   | picker を開く           |
| Workspace | `a`                   | 新規作成                |
| Workspace | `j` / `k`             | picker 内で次 / 前      |
| Tab       | `n`                   | 新規作成                |
| Tab       | `q`                   | 閉じる                  |
| Tab       | `Tab` / `Shift+Tab`   | 次 / 前                 |
| Pane      | `h` / `j` / `k` / `l` | 左 / 下 / 上 / 右へ移動 |
| Pane      | `v` / `-`             | 左右 / 上下分割         |
| Pane      | `x`                   | 閉じる                  |
| Session   | `g`                   | navigator を開く        |
| Session   | `d`                   | detach                  |
```

WezTerm、Terminal.app、Windows Terminal、tmux、Herdr の capability matrix を追加する。Terminal.app と Windows Terminal の非対応 suffix が no-op であること、Hammerspoon/AutoHotkey の app scope、1秒 timeout、nested prefix を明記する。tmux では Workspace=Session、Tab=Window であることも明記する。

- [ ] **Step 4: Windows の実 syntax test が Actions に存在することを確認する**

```bash
rg -n 'windows-latest|Invoke-Tests\.ps1|AutoHotkey' .github/workflows
```

既存 `ci-chezmoi.yml` の Windows lint job は Pester を維持し、AutoHotkey install と syntax check steps を追加する。

```powershell
winget install --id AutoHotkey.AutoHotkey --exact --silent `
  --accept-package-agreements --accept-source-agreements
$autoHotkey = @(
  "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
  "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $autoHotkey) { throw 'AutoHotkey v2 executable was not found after installation' }
& $autoHotkey /ErrorStdOut `
  .\chezmoi\terminals\windows-terminal\terminal-keybindings.ahk --check
if ($LASTEXITCODE -ne 0) { throw "AutoHotkey syntax check failed: $LASTEXITCODE" }
```

install または syntax check が失敗した場合は job を失敗させる。AutoHotkey 不在時の skip 分岐は追加しない。

- [ ] **Step 5: 全ローカル検証を実行する**

```bash
bats tests/bash
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/chezmoi -MinimumCoverage 0
pwsh -NoProfile -File ./scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path ./scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0
HERDR_CONFIG_PATH="$PWD/chezmoi/dot_config/herdr/config.toml" herdr config check
HERDR_CONFIG_PATH="$PWD/chezmoi/AppData/Roaming/herdr/config.toml" herdr config check
wezterm --config-file "$PWD/chezmoi/terminals/wezterm/wezterm.lua" show-keys >/dev/null
luac -p chezmoi/terminals/hammerspoon/init.lua
jq empty chezmoi/terminals/windows-terminal/settings.json
nix fmt -- --fail-on-change
nix flake check --no-build --impure
pre-commit run --all-files
git diff --check
git diff --exit-code -- flake.lock
```

Expected: 全て exit 0。macOS で Windows-only integration が失敗する既知環境差は full Pester の成功へ読み替えず、上記 portable focused suite と GitHub Actions Windows job の両方を必須にする。

- [ ] **Step 6: final diff を設計に照合する**

```bash
git status --short
git diff origin/main...HEAD --stat
git diff origin/main...HEAD -- \
  nix/packages/sets.nix windows/winget/packages.json \
  chezmoi/dot_tmux.conf chezmoi/dot_config/herdr/config.toml \
  chezmoi/AppData/Roaming/herdr/config.toml \
  chezmoi/terminals chezmoi/.chezmoiscripts \
  scripts/powershell/tests tests/bash docs/chezmoi/keybindings.md
rg -n 'TBD|TODO|FIXME|placeholder' \
  docs/chezmoi/keybindings.md chezmoi/terminals \
  chezmoi/.chezmoiscripts scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1
```

Expected: 変更は承認済み設計の範囲だけ。placeholder は0件。`flake.lock` と unrelated files は差分なし。

- [ ] **Step 7: docs と最終回帰テストをコミットする**

```bash
git add docs/chezmoi/keybindings.md \
  scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 \
  .github/workflows/ci-chezmoi.yml
task commit DOTFILES_PATH="$PWD" -- "docs: define unified terminal keybinding contract"
```

---

### Task 7: 実環境を確認し、PR、Actions、merge まで完了する

**Files:**

- Verify: managed source files from Tasks 1–6
- Verify: deployed macOS files under `~/.config/wezterm/`, `~/.hammerspoon/`, and Herdr config path
- No source changes unless verification or review identifies a defect

**Interfaces:**

- Consumes: completed branch、chezmoi apply、GitHub Actions、repository ruleset。
- Produces: macOS runtime evidence、Windows CI evidence、merged PR、最新の local `main`。primary checkout の user-owned `flake.lock` は保持する。

- [ ] **Step 1: macOS へ package と managed config を反映する**

feature worktree の source と lockfile を明示して install を実行する。

```bash
cd /Users/ktome1995/Program/dotfiles/.worktrees/unified-terminal-keybindings
./install.sh
zsh -lic 'command -v hammerspoon >/dev/null || test -d /Applications/Hammerspoon.app'
```

`install.sh` は自身の配置 directory を root として feature worktree を使う。primary checkout の branch 切替や `flake.lock` の上書きはしない。

- [ ] **Step 2: macOS runtime acceptance を実施する**

```bash
test -f ~/.hammerspoon/init.lua
cmp /Users/ktome1995/Program/dotfiles/.worktrees/unified-terminal-keybindings/chezmoi/terminals/hammerspoon/init.lua ~/.hammerspoon/init.lua
wezterm show-keys >/dev/null
HERDR_CONFIG_PATH="$HOME/.config/herdr/config.toml" herdr config check
```

Hammerspoon の Accessibility permission が未付与ならユーザーに OS dialog の承認だけを依頼し、承認後に Terminal.app で以下を手動確認する。

- `Ctrl+Space n/q/Tab/Shift+Tab/v/x`
- unsupported suffix が文字入力されないこと
- Terminal.app 以外では `Ctrl+Space` を捕捉しないこと
- tmux または Herdr 内で `Ctrl+Space Ctrl+Space n` が内側の tab/window を作ること

WezTerm と Herdr では共通 suffix 全件、tmux では Workspace=Session/Tab=Window を確認する。実際に確認していない項目は未検証として記録する。

- [ ] **Step 3: completion verification と review を行う**

`superpowers:verification-before-completion` と `superpowers:requesting-code-review` を使い、Task 6 の全検証を fresh に再実行する。差分に問題があれば修正し、関連テストを赤→緑で追加して `task commit` する。

- [ ] **Step 4: branch を push して PR を作る**

`github:yeet` を使い、コミット範囲、branch、差分、テスト結果を確認してから実行する。

```bash
git push -u origin feat/unified-terminal-keybindings
gh pr create \
  --base main \
  --head feat/unified-terminal-keybindings \
  --title "feat: unify terminal window manager keybindings" \
  --body-file /tmp/unified-terminal-keybindings-pr.md
```

PR body には共通契約、capability boundary、package/deployment、実行したテスト、未実施の実機確認を分けて書く。

- [ ] **Step 5: Actions と review threads を最後まで監視する**

```bash
gh pr checks --watch --fail-fast=false
gh pr view --json number,url,mergeStateStatus,reviewDecision,statusCheckRollup
```

失敗した check は `github:gh-fix-ci` を使ってログから原因を直し、テストを削除・skip・allow-failure に変更して通さない。全 required checks が success になった後、GraphQL で unresolved non-outdated review threads が0件であることと、ruleset の許可する merge method を確認する。

- [ ] **Step 6: PR を merge し local main を fast-forward する**

repository ruleset が許可する method で merge する。

```bash
gh pr merge --merge
git -C /Users/ktome1995/Program/dotfiles status --short --branch
git -C /Users/ktome1995/Program/dotfiles pull --ff-only origin main
```

primary checkout の `flake.lock` が merge 内容と競合する場合は pull を強行せず、未コミット差分を保持したまま停止して報告する。成功時は merge commit、PR URL、Actions 結果、local `main` の commit、保持した user-owned diff を報告する。
