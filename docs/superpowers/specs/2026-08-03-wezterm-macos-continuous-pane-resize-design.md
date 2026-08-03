# WezTerm macOS continuous pane resize keybindings

## Context

macOS の WezTerm では、pane サイズ変更を `Ctrl+Space` leader の後に
`Shift+矢印`を押す操作へ割り当てている。この方式は単発操作には使えるが、
pane 境界を連続調整するたびに leader を押し直す必要があり、リサイズ操作に
適していない。

## Decision

macOS の pane サイズ変更を、iTerm2 で一般的な
`Ctrl+Command+矢印`へ変更する。

- `Ctrl+Command`を押したまま矢印を連打または長押しできるようにする。
- 1回のキーイベントにつき1セル調整し、連続入力で滑らかに変更する。
- 旧 `Ctrl+Space` → `Shift+矢印` の割り当ては削除する。
- pane 移動、分割、zoom、close、window focus の割り当ては変更しない。

## Platform scope

- macOS の WezTerm のみ変更する。
- Windows/Linux の WezTerm は既存の `Alt+Shift+矢印` を維持する。
- Windows Terminal の割り当ては変更しない。

## Documentation

`docs/chezmoi/keybindings.md` の macOS WezTerm pane resize 記載を
`Ctrl+Command+矢印`へ更新し、GUI pane resize の統一ルールとして明示する。

## Verification

- `wezterm show-keys` で `CTRL|SUPER + 矢印` が
  `AdjustPaneSize(<direction>, 1)` に解決されることを確認する。
- 旧 `SHIFT|LEADER + 矢印` が表示されないことを確認する。
- Lua 設定の評価、フォーマット、`git diff --check` を実行する。
- chezmoi 反映後、macOS の WezTerm でキー連打による連続リサイズを確認する。
