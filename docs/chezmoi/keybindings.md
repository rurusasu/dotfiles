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
| `Shift+Enter`      | 複数行入力          | AI CLI / terminal prompt 改行  |
| `Space` (`Leader`) | ツール機能呼び出し  | 検索、エクスプローラ、タブ操作 |
| `Alt` (Shell)      | CLI 補助操作        | fzf/zoxide ウィジェット        |

## 現在の適用状況

### Terminals

- WezTerm
  - `Shift+Enter`: AI CLI / terminal prompt の複数行入力
  - `Ctrl+Shift+H/J/K/L`: ペイン移動
  - `Ctrl+Alt+H/V/X/W`: 分割/close/ズーム
  - `Leader` (`Ctrl+Space`) + `t/x/h/l/1-9`: タブ操作
  - `Leader` (`Ctrl+Space`) + `c/v`: コピー/ペースト
- Windows Terminal
  - `Shift+Enter`: AI CLI / terminal prompt の複数行入力 (`CSI u`)
  - `Ctrl+Enter`: Windows Terminal 用 fallback (`CSI u`)
  - `Ctrl+Shift+H/J/K/L`: ペイン移動
  - `Ctrl+Alt+H/V/X/W`: 分割/close/ズーム
- Warp
  - `Ctrl+Shift+H/J/K/L`: ペイン移動
  - `Ctrl+Alt+H/V`: 分割
  - `Ctrl+Space`: AI natural language search（nvim/WezTerm leader に合わせた統一キー）
  - `Ctrl+Enter`: AI agent へ送信（Warp ハードコード、変更不可）
  - `Ctrl+Y`: AI agent 会話を継続（Warp ハードコード、変更不可）

### Editors

- Neovim
  - `Leader` は `Space`
  - `Space+e`: エクスプローラ
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
  - `Space+aa`: AI チャット toggle (codecompanion)
  - `Space+ai`: AI インライン補助 (codecompanion)
  - `Space+ac`: AI アクションメニュー (codecompanion)
  - `Space+du/dc/dd/dt`: Devcontainer up/connect/down/toggle
- VS Code / Cursor
  - `Vim` 拡張は利用しない
  - terminal focus の `Shift+Enter`: AI CLI / terminal prompt の複数行入力
  - `Ctrl+Shift+H/J/K/L`: editor group 移動
  - `Ctrl+Alt+H/V/X/W`: split/close/toggle widths
  - それ以外は標準キーバインドを優先

### Shells

- zsh
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット
- bash
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット
- PowerShell
  - `Shift+Enter`: PSReadLine `AddLine`
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット (PSReadLine)

### AI CLI

- Claude Code / Codex / terminal 内 AI prompt の複数行入力は `Shift+Enter` に統一する。
- Windows Terminal では `Shift+Enter` を `CSI u` sequence として送る。`Ctrl+Enter` は fallback として同じ用途に割り当てる。
- `Ctrl+J` は押下キーとして使わない。Codex では LF を送る terminal の受信互換としてのみ許可する。

### zoxide + fzf integration

- `Alt+Q` は各 shell で `zoxide query -i` を呼び出し、履歴ベースのディレクトリ候補をインタラクティブ選択する
- `Alt+D` は `fd --absolute-path` + `fzf` でディレクトリ検索して `cd`
- `Alt+T` は `fd` + `fzf` でファイル/ディレクトリを選択してコマンドラインへ挿入
- `Alt+R` は履歴を `fzf` で選択してコマンドラインへ反映

## 運用ルール

- 新しいショートカットを追加する前に、この表のどのグループに属するかを先に決める
- 既存ショートカットと衝突する場合は、`Ctrl+Shift` (移動) を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
