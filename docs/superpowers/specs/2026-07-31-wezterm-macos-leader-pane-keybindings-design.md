# WezTerm macOS leader pane keybindings

## Context

macOSのOption+Shift入力は、キーボードレイアウトやWezTermの合成入力処理の影響を受ける。誤ったキーを押した直後にDeleteを使う操作でも、Option由来のESC/合成状態が残り、pane操作の接頭辞として不便になる。

## Decision

macOSのWezTermでは、pane操作とWezTermウィンドウ切り替えからOption+Shiftを外し、既存のCtrl+Space leaderを接頭辞として使う。

| 操作                       | キー                    |
| -------------------------- | ----------------------- |
| 右pane分割                 | Ctrl+Space → `\|`       |
| 下pane分割                 | Ctrl+Space → `-`        |
| pane移動                   | Ctrl+Space → 矢印       |
| paneサイズ変更             | Ctrl+Space → Shift+矢印 |
| WezTermウィンドウ左/右移動 | Ctrl+Space → h/l        |

既存の `Ctrl+Shift+w`（pane close）、`Ctrl+Alt+w`（pane zoom）、tab操作、Alt単独のfzf/zoxide操作は維持する。Windows Terminalの設定は変更しない。

## Rationale

- Optionをpane操作から外すため、誤入力後のDeleteがmacOS/IME/Meta入力の影響を受けない。
- leaderは既に設定済みで、leader直後のBackspaceも明示的に保護されている。
- Windows側のデファクト操作は維持し、macOSだけ入力環境に合わせる。

## Verification

- `wezterm show-keys --lua` で新しいleader mappingsを確認する。
- WezTerm設定のLua評価と `git diff --check` を実行する。
- terminal deploy scriptで `~/.config/wezterm/wezterm.lua` に反映する。
- macOSのWezTermアプリで分割、移動、サイズ変更、誤入力後のDeleteを手動確認する。
