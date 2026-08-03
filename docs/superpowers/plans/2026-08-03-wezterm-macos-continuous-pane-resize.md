# WezTerm macOS Continuous Pane Resize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS の WezTerm で `Ctrl+Command` を押したまま矢印を連打または長押しし、pane を1セルずつ連続リサイズできるようにする。

**Architecture:** 既存の `is_macos` 分岐内にある4方向の `AdjustPaneSize` バインドだけを、`LEADER|SHIFT`・5セルから `SUPER|CTRL`・1セルへ置き換える。Pester の設定契約テストとキーバインド方針文書を同じ変更で更新し、Windows/Linux 側の `ALT|SHIFT` バインドは維持する。

**Tech Stack:** WezTerm Lua configuration、PowerShell/Pester、chezmoi、Markdown

## Global Constraints

- macOS の WezTerm のみ変更する。
- `Ctrl+Command`を押したまま矢印を連打または長押しできるようにする。
- 1回のキーイベントにつき1セル調整する。
- 旧 `Ctrl+Space` → `Shift+矢印` の割り当ては削除する。
- pane 移動、分割、zoom、close、window focus の割り当ては変更しない。
- Windows/Linux の WezTerm と Windows Terminal の割り当ては変更しない。

---

### Task 1: macOS pane resize を連続入力向けキーへ変更する

**Files:**

- Modify: `scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1:58-141`
- Modify: `chezmoi/terminals/wezterm/wezterm.lua:178-210`
- Modify: `docs/chezmoi/keybindings.md:11-44`

**Interfaces:**

- Consumes: `pane_control_bindings` の macOS/非macOS 分岐と、Pester の文字列契約テスト。
- Produces: macOS では `SUPER|CTRL + Arrow` が `AdjustPaneSize({ direction, 1 })` を実行し、非macOS では既存の `ALT|SHIFT + Arrow` が `AdjustPaneSize({ direction, 5 })` を実行する設定。

- [ ] **Step 1: macOS の新しいリサイズ契約を表す失敗テストを書く**

`scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1` の docs テストへ次を追加する。

```powershell
$docs | Should -Match 'Ctrl\+Command\+矢印' -Because "macOS WezTerm resize should use a repeatable modifier chord"
```

同ファイルの WezTerm テストにある4本の `LEADER|SHIFT` resize assertion を、次へ置き換える。

```powershell
$content | Should -Match '\{ key = "LeftArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Left", 1 \}\) \}'
$content | Should -Match '\{ key = "UpArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Up", 1 \}\) \}'
$content | Should -Match '\{ key = "RightArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Right", 1 \}\) \}'
$content | Should -Match '\{ key = "DownArrow", mods = "SUPER\|CTRL", action = act\.AdjustPaneSize\(\{ "Down", 1 \}\) \}'
$content | Should -Not -Match 'mods = "LEADER\|SHIFT", action = act\.AdjustPaneSize'
```

既存の非macOS `ALT|SHIFT` assertion は変更しない。

- [ ] **Step 2: テストを実行し、現在の設定では失敗することを確認する**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1' -Output Detailed"
```

Expected: FAIL。`Ctrl+Command+矢印`、`SUPER|CTRL` の4方向、または旧 `LEADER|SHIFT` 不在の assertion が失敗する。

- [ ] **Step 3: macOS の WezTerm リサイズバインドを最小変更する**

`chezmoi/terminals/wezterm/wezterm.lua` の macOS 分岐内にある4本を次へ置き換える。

```lua
        -- iTerm2-style pane resize: hold Ctrl+Command and repeat Arrow
        { key = "LeftArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Left", 1 }) },
        { key = "UpArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Up", 1 }) },
        { key = "RightArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Right", 1 }) },
        { key = "DownArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Down", 1 }) },
```

- [ ] **Step 4: キーバインド方針文書を実装と一致させる**

`docs/chezmoi/keybindings.md` の統一ルールへ次を追加する。

```markdown
| `Ctrl+Command` (WezTerm macOS) | GUI pane resize | `Ctrl+Command+矢印` |
```

WezTerm の resize 行を次へ置き換える。

```markdown
- `Ctrl+Command+矢印`: ペイン resize（1セル、連打・長押し対応）
```

運用ルールの macOS pane 操作説明を次へ変更する。

```markdown
- WezTerm macOS の pane 移動・window focus は`Leader`、pane resize は`Ctrl+Command+矢印`、Windows Terminalでは`Alt` / `Alt+Shift`を優先する
```

- [ ] **Step 5: 契約テストとWezTermの設定評価を通す**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1' -Output Detailed"
wezterm --config-file ./chezmoi/terminals/wezterm/wezterm.lua show-keys | rg 'CTRL.*SUPER.*(LeftArrow|UpArrow|RightArrow|DownArrow).*AdjustPaneSize\((Left|Up|Right|Down), 1\)'
if wezterm --config-file ./chezmoi/terminals/wezterm/wezterm.lua show-keys | rg -q 'SHIFT \| LEADER.*AdjustPaneSize'; then exit 1; fi
```

Expected: Pester PASS。`wezterm show-keys` は4方向の `CTRL|SUPER`・1セル binding を表示し、旧 `SHIFT|LEADER` resize は検出されない。

- [ ] **Step 6: フォーマットと差分検証を行う**

```bash
nix fmt -- --fail-on-change
pre-commit run --files scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 chezmoi/terminals/wezterm/wezterm.lua docs/chezmoi/keybindings.md
git diff --check
git diff -- scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 chezmoi/terminals/wezterm/wezterm.lua docs/chezmoi/keybindings.md
```

Expected: すべて exit 0。差分はテスト、macOS の4本の resize binding、対応する文書記載だけに限定される。

- [ ] **Step 7: chezmoi で反映し、実設定を確認する**

```bash
chezmoi apply --force
cmp ./chezmoi/terminals/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua
wezterm show-keys | rg 'CTRL.*SUPER.*(LeftArrow|UpArrow|RightArrow|DownArrow).*AdjustPaneSize\((Left|Up|Right|Down), 1\)'
```

Expected: すべて exit 0。ライブ設定が source of truth と一致し、4方向の新しい binding が有効になる。

- [ ] **Step 8: 変更をコミットする**

```bash
task commit -- "feat: add continuous WezTerm pane resize keys"
```

Expected: format・lint・テストが通り、設定、契約テスト、キーバインド文書だけを含むコミットが作成される。
