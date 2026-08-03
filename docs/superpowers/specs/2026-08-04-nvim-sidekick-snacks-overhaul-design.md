# Neovim Sidekick / Snacks Overhaul Design

## Goal

Sidekick CLI が開いているだけで Snacks picker のフォーカスが奪われる問題を解消し、Sidekick と Snacks の設定を公式 API に沿った独立した plugin spec として整理する。

成功条件は次のとおり。

- Sidekick CLI を右分割で開ける。
- Sidekick から編集ウィンドウへ戻った後、`<leader>ff` で Snacks files picker を開ける。
- Snacks picker の入力フォーカスが Sidekick に移動しない。
- Snacks picker の `<M-a>` で選択項目を現在の Sidekick セッションへ送れる。
- Sidekick CLI 内の `<C-f>` で送信用 file picker を開ける。
- 既存の Sidekick リサイズキーと送信キーを維持する。

## Root Cause

現在の Sidekick spec は、`WinNew` のたびに全ウィンドウを走査し、`w:sidekick_cli` が付いた既存ウィンドウへフォーカスして `wincmd L` を実行する。この autocmd は Sidekick の生成だけでなく、Snacks picker の入力・一覧・preview window の生成でも発火する。そのため Sidekick が非フォーカスでも、新しい Snacks window から Sidekick へフォーカスが移る。

この workaround は tmux mux backend を試した際に追加されたが、直後に mux は無効化され、現在は Sidekick の terminal backend を使用している。現行 Sidekick は `cli.win.layout = "right"` を `nvim_open_win()` の split config に変換するため、グローバルな `WinNew` 補正は不要である。

## Scope

### In scope

- `lua/plugins/init.lua` から Snacks spec を `lua/plugins/snacks.lua` へ移す。
- `lua/plugins/init.lua` から Sidekick spec と専用 resize helper を `lua/plugins/sidekick.lua` へ移す。
- `SidekickForceRight` autocmd とカスタム `config` callback を削除する。
- Sidekick の `cli.win.layout = "right"` を明示する。
- 現在の幅、キーマップ、mux、tool override、Snacks連携の挙動を維持する。
- Pester に設定構造と回帰条件を検証するテストを追加する。
- 実Neovimで Sidekick 非フォーカス時の Snacks picker を確認する。

### Out of scope

- Sidekick、Snacks、Neovim本体のversion変更。
- tmux mux backendの再有効化。
- Sidekick paneの初期幅変更。
- Sidekick/AI CLIの追加。
- `plugins/init.lua` に残る他pluginの全面分割。
- Snacks picker全体のキーマップ再設計。

## Architecture

### `lua/plugins/snacks.lua`

現在の Snacks plugin spec を挙動変更なしで移動する。files、grep、buffers、ghq、lazygit、terminal、image/PDF previewなど、Snacksが所有する設定はこのファイルに集約する。

SnacksからSidekickへ送る`sidekick_send` actionも、Snacks pickerのactionであるためこのファイルに残す。action実行時にだけ`sidekick.cli.picker.snacks`をrequireし、選択中のfile path、grep location、複数選択を現在のCLI sessionへ渡す。

### `lua/plugins/sidekick.lua`

Sidekick plugin specと、Sidekick terminal windowだけを操作するresize helperを配置する。

Sidekickのウィンドウ生成・配置はplugin本体へ委譲する。specは`opts.cli.win.layout = "right"`を明示するが、`WinNew`、`WinEnter`などのグローバルwindow lifecycle eventを追加しない。初期split widthは現状のSidekick defaultを維持し、既存のresize keyだけを追加する。

### `lua/plugins/init.lua`

Snacks・Sidekick以外の既存plugin specだけを保持する。lazy.nvimは`require("lazy").setup("plugins")`で`lua/plugins/*.lua`を自動importするため、loader変更は行わない。

## Interaction Flow

### Open a file in Neovim

1. Sidekickで`<C-z>`を押し、編集windowへ戻る。
2. `<leader>ff`がNormal modeで`Snacks.picker.files()`を開く。
3. Sidekick用のグローバル`WinNew` handlerは存在しないため、Snacksがフォーカスを保持する。
4. `<CR>`で選択したfileをNeovimで開く。

### Send picker context to Sidekick

1. 任意のSnacks pickerを開く。
2. itemを選択し、`<M-a>`を押す。
3. `sidekick.cli.picker.snacks.send()`が選択itemをlocationへ変換する。
4. 現在のSidekick CLI sessionへfile pathや行位置を送る。

### Open Sidekick's send-file picker

1. Sidekick terminal modeで`<C-f>`を押す。
2. Sidekick標準actionがSnacks file pickerを開く。
3. 選択結果を現在のSidekick CLI sessionへ送る。

## Error Handling

- Sidekick windowが既に閉じられている場合、resize helperは無効なwindow IDを検出して何もしない。
- Sidekick layoutがtop/bottomの場合、左右resize helperは何もしない。現行の防御動作を維持する。
- Snacksからの送信時に利用可能なSidekick sessionがない場合は、Sidekick本体の既存エラー通知へ委譲する。独自session stateを持たない。
- plugin load orderを独自autocmdで補正しない。lazy.nvimのdependencyとevent管理に委譲する。

## Testing

### Automated

新しい`NvimSidekick.Tests.ps1`で次を検証する。

- `plugins/sidekick.lua`が存在し、Sidekick specと`layout = "right"`を持つ。
- Sidekick specに`WinNew`、`SidekickForceRight`、`wincmd L`が存在しない。
- resize、focus、toggle、send keymapsが分離後も存在する。
- `plugins/snacks.lua`が存在し、`<leader>ff`と`<M-a>`のSidekick send actionを持つ。
- `plugins/init.lua`に重複したSnacks/Sidekick specが残っていない。

StyLua checkと既存Pester suiteも実行する。

### Runtime smoke test

実際のNeovimで次を確認する。

1. Sidekick Codexを右分割で開く。
2. `<C-z>`で編集windowへ戻る。
3. `<leader>ff`でSnacks files pickerを開く。
4. pickerのinput windowがcurrent windowであり続けることを確認する。
5. `<M-a>`で選択fileをSidekickへ送れることを確認する。
6. Sidekickのresize keyが継続して動くことを確認する。

## Migration and Rollback

設定のsource of truthは引き続き`chezmoi/dot_config/nvim`とする。chezmoi applyでlive configへ反映する。

rollbackは新しい2つのspec fileを削除し、移動したblockを`plugins/init.lua`へ戻すことで可能。ただし`SidekickForceRight` autocmdは問題の直接原因なのでrollback対象に含めず、必要ならSidekick公式の`cli.win` optionで配置を調整する。
