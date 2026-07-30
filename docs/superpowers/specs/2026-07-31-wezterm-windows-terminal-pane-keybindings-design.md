# WezTerm / Windows Terminal ペイン操作キー統一設計

## 目的

macOS の WezTerm で `Ctrl+Alt+\\` / `Ctrl+Alt+-` を使ったペイン分割が、Option と記号キーの組み合わせによる特殊入力の影響を受けている。Windows Terminal と WezTerm の共通操作を Windows Terminal の標準的なペイン操作へ寄せ、macOS でも記号キー入力をシェルへ漏らさず操作できるようにする。

## 対象

- `chezmoi/terminals/wezterm/wezterm.lua`
- `chezmoi/terminals/windows-terminal/settings.json`
- `docs/chezmoi/keybindings.md`

既存のタブ操作、フォントサイズ操作、WezTerm 固有のウィンドウフォーカス操作は対象外とする。

## 共通キー設計

| 操作           | WezTerm           | Windows Terminal  |
| -------------- | ----------------- | ----------------- |
| 右分割         | `Alt+Shift+=`     | `alt+shift+plus`  |
| 下分割         | `Alt+Shift+-`     | `alt+shift+minus` |
| 左ペインへ移動 | `Alt+Left`        | `alt+left`        |
| 上ペインへ移動 | `Alt+Up`          | `alt+up`          |
| 右ペインへ移動 | `Alt+Right`       | `alt+right`       |
| 下ペインへ移動 | `Alt+Down`        | `alt+down`        |
| 左へリサイズ   | `Alt+Shift+Left`  | `alt+shift+left`  |
| 上へリサイズ   | `Alt+Shift+Up`    | `alt+shift+up`    |
| 右へリサイズ   | `Alt+Shift+Right` | `alt+shift+right` |
| 下へリサイズ   | `Alt+Shift+Down`  | `alt+shift+down`  |
| ペインを閉じる | `Ctrl+Shift+W`    | `ctrl+shift+w`    |

Windows Terminal の `swapPane` による `Alt+Shift+H/J/K/L` は既存のまま維持する。WezTerm の `Alt+Shift+H/L` による別ウィンドウフォーカスも既存のまま維持するため、この2つはプラットフォーム固有操作として扱う。

## 変更方針

- 旧ペイン操作の `Ctrl+Alt+\\`、`Ctrl+Alt+-`、`Ctrl+Alt+X` を削除する。
- 旧ペイン移動・リサイズの `Alt+H/J/K/L`、`Ctrl+Alt+H/J/K/L` を矢印キーへ置き換える。
- WezTerm の `Ctrl+Shift+W` を既定割り当て無効化だけにせず、現在のペインを閉じるアクションへ割り当てる。
- Windows Terminal は既存の `splitMode: duplicate` を維持し、新しいペインで現在のプロファイルを複製する。
- WezTerm と Windows Terminal の設定ファイル以外に、利用者向け一覧 `docs/chezmoi/keybindings.md` の該当表を更新する。

## 反映と検証

1. WezTerm 設定を `wezterm show-keys --lua` で評価し、分割・移動・リサイズ・close の各アクションが新キーに割り当てられていることを確認する。
2. Windows Terminal JSON を `jq` で検証し、同じ操作のキー定義を確認する。
3. ドキュメントの旧キー表記を検索し、対象操作について残っていないことを確認する。
4. 実環境では `chezmoi apply` 後に WezTerm / Windows Terminal を再起動し、左右・上下分割、移動、リサイズ、close を手動確認する。

## 受け入れ条件

- macOS WezTerm で `Alt+Shift+=` または `Alt+Shift+-` を押したとき、`<ffffffff>` などの文字がシェルへ入力されず、ペインが分割される。
- Windows Terminal と WezTerm で、共通操作のキーと方向が一致する。
- 既存のタブ操作、フォントサイズ操作、WezTerm 固有の別ウィンドウフォーカスが壊れない。
- 設定評価、JSON 構文、旧キー表記の検証がすべて成功する。
