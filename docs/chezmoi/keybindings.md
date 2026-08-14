# キーバインド統一方針

`chezmoi` で管理する `shells` / `editors` / `terminals` のキー設計方針。

## 目的

- コンテキストが変わっても同じ指の動きで操作できるようにする
- OS/IME と競合しやすいキーの利用範囲を狭くする
- `Vim` 拡張への依存を避け、標準機能ベースで運用する

## 統一ルール

| グループ                            | 役割                                  | 例                                  |
| ----------------------------------- | ------------------------------------- | ----------------------------------- |
| `Ctrl+Space`                        | terminal Window Manager prefix        | `Ctrl+Space` + suffix               |
| `Ctrl+Space Ctrl+Space`             | nested terminal へ prefix を1回転送   | `Ctrl+Space Ctrl+Space` + suffix    |
| `Ctrl+Command` (WezTerm macOS)      | 契約外の GUI pane resize              | `Ctrl+Command+矢印`                 |
| `Command+Alt` (WezTerm macOS)       | 契約外の GUI window focus             | `Command+Alt+H/L`                   |
| `Alt+Shift` (WezTerm Windows/Linux) | 契約外の GUI window focus/pane resize | `Alt+Shift+H/L` / `Alt+Shift+矢印`  |
| `Ctrl`                              | Unix/Vim/tmux focus                   | `Ctrl+H/J/K/L`                      |
| `Shift+Enter`                       | 複数行入力                            | AI CLI / terminal prompt 改行       |
| `Space` (`Leader`)                  | editor 機能呼び出し                   | 検索、エクスプローラ、タブ操作      |
| `Alt` (Shell)                       | CLI 補助操作                          | fzf/zoxide ウィジェット (`Q/D/T/R`) |

## 現在の適用状況

### Terminals

terminal Window Manager の共通 prefix は `Ctrl+Space`。prefix に続けて、次の共通 suffix を入力する。

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

target ごとの capability は次のとおり。非対応 suffix は別のキーへフォールバックせず no-op として消費する。

| target           | Workspace                | Tab               | Pane                             | Session        |
| ---------------- | ------------------------ | ----------------- | -------------------------------- | -------------- |
| WezTerm          | 対応                     | 対応              | 対応                             | 対応           |
| Terminal.app     | 非対応 (no-op)           | 対応              | `v` / `x` のみ対応、ほかは no-op | 非対応 (no-op) |
| Windows Terminal | Workspace 非対応 (no-op) | 対応              | 対応                             | 非対応 (no-op) |
| tmux             | 対応 (Workspace=Session) | 対応 (Tab=Window) | 対応                             | 対応           |
| Herdr            | 対応                     | 対応              | 対応                             | 対応           |

- WezTerm は組み込み leader を使い、prefix timeout は1秒。
- Terminal.app は Hammerspoon adapter が前面の `com.apple.Terminal` だけを対象にし、prefix timeout は1秒。Workspace、Session、上下分割 (`-`)、方向 pane focus (`h/j/k/l`) は no-op。
- Windows Terminal は AutoHotkey v2 adapter が前面の `WindowsTerminal.exe` だけを対象にし、prefix timeout は1秒。Workspace / Session は非対応で no-op。
- tmux と Herdr は各アプリの native prefix/key table を使う。tmux では Workspace=Session、Tab=Window として扱う。
- nested terminal では `Ctrl+Space Ctrl+Space` を押すと内側へ `Ctrl+Space` を1回だけ転送する。その後に共通 suffix を入力することで、内側の tmux/Herdr を操作できる。

Hammerspoon の初回設定は次の順で行う。

1. `open -a Hammerspoon` で Hammerspoon を一度起動する。
2. macOS の「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で Hammerspoon を許可する。
3. 許可後、Hammerspoon のメニューバーアイコンから `Reload Config` を実行する。
4. Terminal.app を前面にして `Ctrl+Space n` で新規 tab が開くこと、Terminal.app 以外では同じ入力が捕捉されないことを確認する。

Window Manager 契約外の操作は維持する。WezTerm の `Ctrl+Command+矢印` pane resize、macOS の `Command+Alt+H/L` window focus、Windows/Linux の `Alt+Shift+H/L` window focus と `Alt+Shift+矢印` pane resize、`Ctrl+Alt+W` pane zoom が該当する。WezTerm の `Shift+Enter` と Windows Terminal の `Shift+Enter` / `Ctrl+Enter` も複数行入力用として維持する。

### Editors

- Neovim
  - `Leader` は `Space`
  - `Ctrl+H/J/K/L`: window 移動（tmux 境界越えも同じ）
  - `Ctrl+Z`: undo
  - `Ctrl+Y`: redo
  - `Space+e`: エクスプローラ
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
  - `Space+aa`: AI チャット toggle (codecompanion)
  - `Space+ai`: AI インライン補助 (codecompanion)
  - `Space+ac`: AI アクションメニュー (codecompanion)
  - `Space+du/dc/dd/dt`: Devcontainer up/connect/down/toggle
- VS Code / Cursor
  - `Vim` 拡張は利用しない
  - terminal focus の `Shift+Enter`: AI CLI / terminal prompt の複数行入力
  - `Alt+H/J/K/L`: editor group 移動
  - `Alt+Shift+H/J/K/L`: editor group move
  - `Ctrl+Alt+\` / `Ctrl+Alt+-` / `Ctrl+Alt+X/W`: split/close/toggle widths
  - それ以外は標準キーバインドを優先
- Zed
  - `Alt+H/J/K/L`: pane 移動
  - `Ctrl+Alt+\` / `Ctrl+Alt+-` / `Ctrl+Alt+X/W`: split/close/zoom

### Shells

- tmux (Unix/Linux/WSL)
  - `Ctrl+H/J/K/L`: pane 移動（vim-tmux-navigator と共有）
  - terminal Window Manager 操作は上記の `Ctrl+Space` 共通契約を使う
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
- terminal の Workspace/Tab/Pane/Session 操作は `Ctrl+Space` と共通 suffix を優先する
- target が持たない capability は no-op とし、target 固有の代替キーを共通契約へ混ぜない
- nested terminal の prefix 転送は `Ctrl+Space Ctrl+Space` に統一する
- WezTerm の直接 window focus / pane resize は共通契約外の補助操作として維持する
- tmux/Neovim など Unix/Vim 系は `Ctrl+H/J/K/L` を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
