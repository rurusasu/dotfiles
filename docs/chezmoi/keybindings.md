# キーバインド統一方針

`chezmoi` で管理する `shells` / `editors` / `terminals` のキー設計方針。

## 目的

- コンテキストが変わっても同じ指の動きで操作できるようにする
- OS/IME と競合しやすいキーの利用範囲を狭くする
- `Vim` 拡張への依存を避け、標準機能ベースで運用する

## 統一ルール

| グループ           | 役割                | 例                             |
| ------------------ | ------------------- | ------------------------------ |
| `Ctrl+Shift`       | 移動/ナビゲーション | ペイン移動 (`H/J/K/L`)         |
| `Ctrl+Alt`         | レイアウト変更      | 分割、ペイン close、ズーム     |
| `Space` (`Leader`) | ツール機能呼び出し  | 検索、エクスプローラ、タブ操作 |
| `Alt` (Shell)      | CLI 補助操作        | fzf/zoxide ウィジェット        |

## 現在の適用状況

### Terminals

- WezTerm
  - `Ctrl+Shift+H/J/K/L`: ペイン移動
  - `Ctrl+Alt+H/V/X/W`: 分割/close/ズーム
  - `Leader` (`Ctrl+Space`) + `t/x/h/l/1-9`: タブ操作
  - `Leader` (`Ctrl+Space`) + `c/v`: コピー/ペースト
- Windows Terminal
  - `Ctrl+Shift+H/J/K/L`: ペイン移動
  - `Ctrl+Alt+H/V/X/W`: 分割/close/ズーム

### Editors

- Neovim
  - `Leader` は `Space`
  - `Space+e`: エクスプローラ
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
- VS Code / Cursor
  - `Vim` 拡張は利用しない
  - `Ctrl+Shift+H/J/K/L`: editor group 移動
  - `Ctrl+Alt+H/V/X/W`: split/close/toggle widths
  - それ以外は標準キーバインドを優先

### Shells

- zsh
  - `Alt+Z`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット
- bash
  - `Alt+Z`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット
- PowerShell
  - `Alt+Z`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット (PSReadLine)

### zoxide + fzf integration

- `Alt+Z` は各 shell で `zoxide query -i` を呼び出し、履歴ベースのディレクトリ候補をインタラクティブ選択する
- `Alt+D` は `fd --absolute-path` + `fzf` でディレクトリ検索して `cd`
- `Alt+T` は `fd` + `fzf` でファイル/ディレクトリを選択してコマンドラインへ挿入
- `Alt+R` は履歴を `fzf` で選択してコマンドラインへ反映

## 運用ルール

- 新しいショートカットを追加する前に、この表のどのグループに属するかを先に決める
- 既存ショートカットと衝突する場合は、`Ctrl+Shift` (移動) を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
