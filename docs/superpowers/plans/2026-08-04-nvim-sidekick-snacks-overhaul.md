# Neovim Sidekick / Snacks Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sidekickが非フォーカスで開いている状態でもSnacks pickerがフォーカスを保持し、SnacksとSidekickの設定を独立したlazy.nvim specへ整理する。

**Architecture:** `plugins/init.lua`に同居しているSnacksとSidekickのspecを、それぞれ`plugins/snacks.lua`と`plugins/sidekick.lua`へ機械的に分離する。Sidekickの配置は公式`cli.win.layout = "right"`へ委譲し、全windowに作用する`WinNew` workaroundを削除する。Pesterでspec境界、キーマップ維持、workaround不在を固定する。

**Tech Stack:** Neovim 0.12、Lua、lazy.nvim、folke/snacks.nvim、folke/sidekick.nvim、PowerShell 7、Pester 6、StyLua、chezmoi

## Global Constraints

- 設定のsource of truthは`chezmoi/dot_config/nvim`とする。
- Sidekick、Snacks、Neovim本体のversionを変更しない。
- `cli.mux.enabled = false`を維持する。
- Sidekick paneの初期幅を変更しない。
- `<leader>ff`、`<M-a>`、`<C-f>`、Sidekick resize/send keymapsの挙動を維持する。
- `plugins/init.lua`に残る他pluginは分割しない。
- commitは`task commit DOTFILES_PATH="$PWD" -- "<message>"`を使用する。

---

### Task 1: Sidekick / Snacks構造回帰テスト

**Files:**

- Create: `scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1`
- Read: `chezmoi/dot_config/nvim/lua/plugins/init.lua`

**Interfaces:**

- Consumes: lazy.nvimが`lua/plugins/*.lua`をplugin specとして自動importする既存構成。
- Produces: `plugins/snacks.lua`、`plugins/sidekick.lua`、公式layout、既存keymaps、workaround不在を検証するPester suite。

- [ ] **Step 1: 失敗する構造テストを書く**

`scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1`を次の内容で作成する。

```powershell
#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:pluginsDir = Join-Path $script:repoRoot "chezmoi/dot_config/nvim/lua/plugins"
    $script:initPath = Join-Path $script:pluginsDir "init.lua"
    $script:snacksPath = Join-Path $script:pluginsDir "snacks.lua"
    $script:sidekickPath = Join-Path $script:pluginsDir "sidekick.lua"
    $script:initContent = Get-Content -LiteralPath $script:initPath -Raw
}

Describe 'Neovim Sidekick and Snacks plugin boundaries' {
    It 'should keep Snacks in its own plugin spec' {
        Test-Path -LiteralPath $script:snacksPath -PathType Leaf | Should -BeTrue
        $snacks = Get-Content -LiteralPath $script:snacksPath -Raw
        $snacks | Should -Match '"folke/snacks\.nvim"'
        $snacks | Should -Match '"<leader>ff"'
        $snacks | Should -Match '\["<a-a>"\]'
        $snacks | Should -Match 'sidekick\.cli\.picker\.snacks'
    }

    It 'should keep Sidekick in its own plugin spec' {
        Test-Path -LiteralPath $script:sidekickPath -PathType Leaf | Should -BeTrue
        $sidekick = Get-Content -LiteralPath $script:sidekickPath -Raw
        $sidekick | Should -Match '"folke/sidekick\.nvim"'
        $sidekick | Should -Match 'layout = "right"'
        $sidekick | Should -Match '"<C-.>"'
        $sidekick | Should -Match '"<leader>aa"'
        $sidekick | Should -Match '"<leader>af"'
        $sidekick | Should -Match '"<C-S-h>"'
        $sidekick | Should -Match '"<C-S-l>"'
        $sidekick | Should -Match 'enabled = false'
    }

    It 'should not override global window creation or steal picker focus' {
        $sidekick = Get-Content -LiteralPath $script:sidekickPath -Raw
        $sidekick | Should -Not -Match 'WinNew'
        $sidekick | Should -Not -Match 'SidekickForceRight'
        $sidekick | Should -Not -Match 'wincmd L'
        $sidekick | Should -Not -Match 'nvim_set_current_win'
    }

    It 'should remove duplicate Snacks and Sidekick specs from init.lua' {
        $script:initContent | Should -Not -Match '"folke/snacks\.nvim"'
        $script:initContent | Should -Not -Match '"folke/sidekick\.nvim"'
        $script:initContent | Should -Not -Match 'resize_sidekick_cli'
    }
}
```

- [ ] **Step 2: テストが期待どおり失敗することを確認する**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1' -Output Detailed"
```

Expected: 4 tests fail because `snacks.lua` and `sidekick.lua` do not exist and the old specs remain in `init.lua`.

---

### Task 2: SnacksとSidekickのspec分離

**Files:**

- Create: `chezmoi/dot_config/nvim/lua/plugins/snacks.lua`
- Create: `chezmoi/dot_config/nvim/lua/plugins/sidekick.lua`
- Modify: `chezmoi/dot_config/nvim/lua/plugins/init.lua`
- Test: `scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1`

**Interfaces:**

- Consumes: Task 1の4つのPester contract。
- Produces: lazy.nvimが直接ロードできるSnacks specとSidekick spec。Sidekick specは`opts.cli.win.layout = "right"`を公開し、グローバルwindow autocmdを登録しない。

- [ ] **Step 1: Snacks specを挙動変更なしで移動する**

`plugins/init.lua`の`-- UI utilities + lazygit float`コメントから、その直後にある`"folke/snacks.nvim"` specの閉じ`},`までを1つの連続blockとして切り出す。終端は`-- AI sidekick: AI CLI terminal`コメントの直前である。`plugins/snacks.lua`では、そのblockを新しい`return {`と`}`の間へ置く。picker、lazygit、terminal、image/PDF preview、`sidekick_send`を含むblock内部は編集しない。

追加するwrapperは次の2行だけとする。

```lua
return {
}
```

切り出したSnacks spec全体を、この2行の間へ配置する。

移動前後のblockを`git diff --word-diff=porcelain`で確認し、indent以外のSnacks設定差分がないことを確認する。

- [ ] **Step 2: Sidekick helperとspecを移動し、workaroundを削除する**

`plugins/init.lua`先頭の`resize_sidekick_cli`と`resize_sidekick_cli_toward`を切り出す。さらに`-- AI sidekick: AI CLI terminal`コメントからSidekick specの閉じ`},`までを切り出す。終端は`-- Tmux pane navigation`コメントの直前である。両helper、`return {`、Sidekick spec、`}`の順で`plugins/sidekick.lua`へ配置する。

helperは次の内容をそのまま使用する。

```lua
local function resize_sidekick_cli(terminal, delta)
    local win = terminal and terminal.win
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local layout = terminal.opts and terminal.opts.layout or "right"
    if layout == "float" then
        local cfg = vim.api.nvim_win_get_config(win)
        cfg.width = math.max(20, (cfg.width or vim.api.nvim_win_get_width(win)) + delta)
        cfg.height = math.max(5, (cfg.height or vim.api.nvim_win_get_height(win)) + delta)
        vim.api.nvim_win_set_config(win, cfg)
    elseif layout == "top" or layout == "bottom" then
        vim.api.nvim_win_set_height(win, math.max(5, vim.api.nvim_win_get_height(win) + delta))
    else
        vim.api.nvim_win_set_width(win, math.max(20, vim.api.nvim_win_get_width(win) + delta))
    end
end

local function resize_sidekick_cli_toward(terminal, direction)
    local layout = terminal.opts and terminal.opts.layout or "right"
    if layout == "top" or layout == "bottom" then
        return
    end

    local delta = direction == "left" and 5 or -5
    if layout == "left" then
        delta = -delta
    end
    resize_sidekick_cli(terminal, delta)
end

```

Sidekick spec内の`win = {`直後へ、唯一の新しいlayout設定を追加する。

```lua
win = {
    layout = "right",
    keys = {
```

`resize_grow`、`resize_shrink`、`resize_left`、`resize_right`を含む既存`keys` tableと、global `keys` tableの`<C-.>`および`<leader>a*` entriesは内容を変更しない。

移動元の`config = function(_, opts)`からSidekick spec末尾直前の`end,`までは、新fileへ移さず完全に削除する。このblockには`require("sidekick").setup(opts)`、`nvim_create_autocmd("WinNew")`、`SidekickForceRight`、全window走査、`nvim_set_current_win`、`wincmd L`が含まれる。

```lua
-- No config callback is present in the final Sidekick spec.
```

lazy.nvimは`opts`があるspecに対して`require("sidekick").setup(opts)`を呼ぶため、代替`config` callbackは追加しない。

- [ ] **Step 3: 構造テストを通す**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1' -Output Detailed"
```

Expected: 4 passed, 0 failed.

- [ ] **Step 4: Lua formattingと構文ロードを確認する**

Run:

```bash
stylua --check chezmoi/dot_config/nvim
nvim --headless -u NONE \
  "+lua package.path = '$PWD/chezmoi/dot_config/nvim/lua/?.lua;$PWD/chezmoi/dot_config/nvim/lua/?/init.lua;' .. package.path; assert(type(require('plugins.snacks')) == 'table'); assert(type(require('plugins.sidekick')) == 'table')" \
  +qa
```

Expected: both commands exit 0 without Lua errors.

- [ ] **Step 5: 実装とテストをコミットする**

Run:

```bash
task commit DOTFILES_PATH="$PWD" -- "fix(nvim): isolate sidekick window lifecycle"
```

Expected: formatting、pre-commit、Pesterが成功し、Snacks/Sidekick specとtestが1 commitになる。

---

### Task 3: 実環境への反映とフォーカス回帰検証

**Files:**

- Verify: `chezmoi/dot_config/nvim/lua/plugins/snacks.lua`
- Verify: `chezmoi/dot_config/nvim/lua/plugins/sidekick.lua`
- Verify deployed: `~/.config/nvim/lua/plugins/snacks.lua`
- Verify deployed: `~/.config/nvim/lua/plugins/sidekick.lua`

**Interfaces:**

- Consumes: Task 2の分離済みplugin specs。
- Produces: live NeovimでSidekick非フォーカス時にSnacksが操作可能である確認結果。

- [ ] **Step 1: 全関連テストを実行する**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './scripts/powershell/tests/chezmoi/NvimSidekick.Tests.ps1','./scripts/powershell/tests/chezmoi/NvimShell.Tests.ps1' -Output Detailed"
stylua --check chezmoi/dot_config/nvim
pre-commit run --all-files
```

Expected: Pester 8 passed、StyLua exit 0、全pre-commit hooks passed。

- [ ] **Step 2: worktreeのchezmoi sourceをlive configへ反映する**

Run:

```bash
chezmoi -S "$PWD/chezmoi" apply --force ~/.config/nvim
```

Expected: `~/.config/nvim/lua/plugins/snacks.lua`と`sidekick.lua`が作成され、live `plugins/init.lua`から両specが除去される。

- [ ] **Step 3: live Neovimで操作を確認する**

確認手順:

```text
1. Neovimを再起動する。
2. SidekickからCodexを右分割で開く。
3. Ctrl+zで編集windowへ戻る。
4. Space f fでSnacks files pickerを開く。
5. pickerへ文字入力でき、Sidekickへフォーカスが戻らないことを確認する。
6. Alt+aで選択fileを現在のCodex sessionへ送る。
7. Codexへ戻り、Ctrl+Shift+h/lで幅変更を確認する。
```

Expected: pickerがフォーカスを保持し、既存の送信・resize操作も動作する。

- [ ] **Step 4: 最終diffとworktree状態を確認する**

Run:

```bash
git diff origin/main...HEAD --check
git diff origin/main...HEAD --stat
git status --short --branch
```

Expected: design、plan、2 plugin specs、init cleanup、Pester testだけが差分で、working treeはclean。
