# Terminal Pane Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WezTerm と Windows Terminal の共通ペイン操作を、Windows Terminal 標準に近い矢印キー中心のキー体系へ統一する。

**Architecture:** 既存のOS別設定を維持し、WezTermのLua設定とWindows TerminalのJSON設定に同じ操作意味を登録する。ドキュメントの共通キー表も同じ定義へ更新し、設定評価と文字列検査でクロスプラットフォームの対応を検証する。

**Tech Stack:** WezTerm Lua configuration, Windows Terminal JSON, jq, rg, treefmt/pre-commit.

## Global Constraints

- macOS WezTermで`<ffffffff>`などの特殊文字をシェルへ入力させない。
- 共通操作はWindows TerminalとWezTermでキーと方向を一致させる。
- 既存のタブ操作、フォントサイズ操作、WezTerm固有の別ウィンドウフォーカスは維持する。
- Windows Terminalの既存`splitMode: duplicate`は維持する。
- 変更対象は`chezmoi/terminals/wezterm/wezterm.lua`、`chezmoi/terminals/windows-terminal/settings.json`、`docs/chezmoi/keybindings.md`に限定する。

---

### Task 1: WezTerm のペイン操作を矢印キーへ移行

**Files:**

- Modify: `chezmoi/terminals/wezterm/wezterm.lua:119-189`

**Interfaces:**

- Consumes: 既存の`config.keys`、`wezterm.action`、`CurrentPaneDomain`。
- Produces: WezTermでWindows Terminalと同じ分割・移動・リサイズ・close操作を提供するキー割り当て。

- [ ] **Step 1: 新しいキー割り当てを検証するコマンドを先に定義する**

実装後に次のコマンドが検証できるよう、期待する割り当てを固定する。

```bash
wezterm --config-file chezmoi/terminals/wezterm/wezterm.lua show-keys --lua \
  | rg "SplitHorizontal|SplitVertical|ActivatePaneDirection|AdjustPaneSize|CloseCurrentPane"
```

期待するキーは、分割が`ALT|SHIFT`の`+`と`-`（物理操作は`Alt+Shift+=`と`Alt+Shift+-`）、移動が`ALT`の`LeftArrow`/`UpArrow`/`RightArrow`/`DownArrow`、リサイズが`ALT|SHIFT`の同じ矢印、closeが`CTRL|SHIFT`の`w`である。

- [ ] **Step 2: 記号キー依存の旧ペイン操作を削除する**

次の既存割り当てを削除する。

```lua
{ key = "\\", mods = "CTRL|ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
{ key = "-", mods = "CTRL|ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
{ key = "x", mods = "CTRL|ALT", action = act.CloseCurrentPane({ confirm = true }) },
```

また、`Alt+H/J/K/L`のペイン移動と`Ctrl+Alt+H/J/K/L`のリサイズも削除する。ただし`Alt+Shift+H/L`の別ウィンドウフォーカスは残す。

- [ ] **Step 3: Windows Terminal標準相当の割り当てを追加する**

`config.keys`に次を追加する。

```lua
{ key = "+", mods = "ALT|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
{ key = "-", mods = "ALT|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
{ key = "LeftArrow", mods = "ALT", action = act.ActivatePaneDirection("Left") },
{ key = "UpArrow", mods = "ALT", action = act.ActivatePaneDirection("Up") },
{ key = "RightArrow", mods = "ALT", action = act.ActivatePaneDirection("Right") },
{ key = "DownArrow", mods = "ALT", action = act.ActivatePaneDirection("Down") },
{ key = "LeftArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
{ key = "UpArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
{ key = "RightArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
{ key = "DownArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = true }) },
```

`Ctrl+Shift+W`を既定割り当て無効化するだけの既存行は削除し、上記のcloseアクションが有効になるようにする。

- [ ] **Step 4: WezTerm設定の評価結果を確認する**

Run: `wezterm --config-file chezmoi/terminals/wezterm/wezterm.lua show-keys --lua | rg "SplitHorizontal|SplitVertical|ActivatePaneDirection|AdjustPaneSize|CloseCurrentPane"`

Expected: 新しい`ALT`/`ALT|SHIFT`矢印キー、`ALT|SHIFT`の`=`/`-`、`CTRL|SHIFT`の`w`が出力され、旧`CTRL|ALT`のペイン操作が出力されない。

- [ ] **Step 5: Commit**

```bash
git add chezmoi/terminals/wezterm/wezterm.lua
git commit -m "feat: align WezTerm pane keybindings"
```

### Task 2: Windows Terminal とキー一覧ドキュメントを更新

**Files:**

- Modify: `chezmoi/terminals/windows-terminal/settings.json:122-155`
- Modify: `docs/chezmoi/keybindings.md:12-40`

**Interfaces:**

- Consumes: Windows Terminalの既存`User.splitPane.horizontal`、`User.splitPane.vertical`、`User.moveFocus.*`、`User.resizePane.*`、`User.closePane`アクション。
- Produces: WezTermと同じキー・方向のWindows Terminal設定と利用者向けキー一覧。

- [ ] **Step 1: Windows Terminalのキー値を置き換える**

`keybindings`配列の共通ペイン操作を次の値へ変更する。

```json
{ "id": "User.splitPane.horizontal", "keys": "alt+shift+plus" },
{ "id": "User.splitPane.vertical", "keys": "alt+shift+minus" },
{ "id": "User.closePane", "keys": "ctrl+shift+w" },
{ "id": "User.moveFocus.left", "keys": "alt+left" },
{ "id": "User.moveFocus.up", "keys": "alt+up" },
{ "id": "User.moveFocus.right", "keys": "alt+right" },
{ "id": "User.moveFocus.down", "keys": "alt+down" },
{ "id": "User.resizePane.left", "keys": "alt+shift+left" },
{ "id": "User.resizePane.up", "keys": "alt+shift+up" },
{ "id": "User.resizePane.right", "keys": "alt+shift+right" },
{ "id": "User.resizePane.down", "keys": "alt+shift+down" }
```

`splitMode: duplicate`、swap pane、タブ、フォントサイズ、検索の既存設定は変更しない。

- [ ] **Step 2: 共通ルールとTerminals節を更新する**

`docs/chezmoi/keybindings.md`で、`Ctrl+Alt`を共通ペイン操作として説明している行を削除し、次の内容へ更新する。

```text
Alt + 矢印: GUI pane focus
Alt+Shift + 矢印: GUI pane resize
Alt+Shift + =/-: GUI pane split right/down
Ctrl+Shift+W: GUI pane close
```

WezTermとWindows Terminalの各項目をこの対応表に合わせ、Windows固有の`Alt+Shift+H/J/K/L` swapとWezTerm固有の`Alt+Shift+H/L` window focusは注記として残す。VS Code、Zed、tmuxの既存キー説明は変更しない。

- [ ] **Step 3: JSONと旧キー表記を検証する**

Run: `jq empty chezmoi/terminals/windows-terminal/settings.json`

Run: `rg -n "Ctrl\\+Alt|ctrl\\+alt|Alt\\+H/J/K/L|alt\\+h|alt\\+j|alt\\+k|alt\\+l" docs/chezmoi/keybindings.md chezmoi/terminals/windows-terminal/settings.json`

Expected: 対象の共通ペイン操作について旧キー表記が残らず、Windows固有のswap操作と他アプリの既存表記だけが意図どおり残る。

- [ ] **Step 4: Commit**

```bash
git add chezmoi/terminals/windows-terminal/settings.json docs/chezmoi/keybindings.md
git commit -m "docs: align terminal pane keybinding reference"
```

### Task 3: 全体検証と反映手順の確認

**Files:**

- Test: `chezmoi/terminals/wezterm/wezterm.lua`
- Test: `chezmoi/terminals/windows-terminal/settings.json`
- Test: `docs/chezmoi/keybindings.md`

**Interfaces:**

- Consumes: Task 1とTask 2のコミット済み設定。
- Produces: 設定評価、JSON構文、差分、既存フックの検証結果。

- [ ] **Step 1: 設定・JSON・差分の検証を実行する**

```bash
wezterm --config-file chezmoi/terminals/wezterm/wezterm.lua show-keys --lua \
  | rg "ALT.*(LeftArrow|UpArrow|RightArrow|DownArrow)|ALT.*[=-]|CTRL.*SHIFT.*w|SplitHorizontal|SplitVertical|AdjustPaneSize|CloseCurrentPane"
jq empty chezmoi/terminals/windows-terminal/settings.json
git diff --check HEAD~2..HEAD
```

Expected: WezTermの全新割り当てが出力され、`jq`と`git diff --check`が終了コード0になる。

- [ ] **Step 2: リポジトリの対象チェックを実行する**

```bash
pre-commit run --files \
  chezmoi/terminals/wezterm/wezterm.lua \
  chezmoi/terminals/windows-terminal/settings.json \
  docs/chezmoi/keybindings.md
```

Expected: 該当フックがすべて成功する。自動整形でファイルが変更された場合は差分を確認して再ステージする。

- [ ] **Step 3: 実環境への反映手順を記録する**

macOSでは次を実行する。

```bash
chezmoi apply
```

その後WezTermを再起動し、`Alt+Shift+=`、`Alt+Shift+-`、`Alt+矢印`、`Alt+Shift+矢印`、`Ctrl+Shift+W`を手動確認する。Windowsでは`dotf chezmoi`後にWindows Terminalを再起動して同じ操作を確認する。
