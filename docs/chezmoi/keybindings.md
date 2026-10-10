# キーバインド統一方針

Nix で管理するデスクトップ配列と、`chezmoi` で管理する `shells` / `terminals` のキー設計方針。

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
| `Ctrl+Command+M` (macOS)            | GUI window zoom / restore             | `Ctrl+Command+M`                    |
| `Command+Alt` (WezTerm macOS)       | 契約外の GUI window focus             | `Command+Alt+H/L`                   |
| `Alt+Shift` (WezTerm Windows/Linux) | 契約外の GUI window focus/pane resize | `Alt+Shift+H/L` / `Alt+Shift+矢印`  |
| `Ctrl`                              | Unix/Vim focus                        | `Ctrl+H/J/K/L`                      |
| `Shift+Enter`                       | 複数行入力                            | AI CLI / terminal prompt 改行       |
| `Space` (`Leader`)                  | editor 機能呼び出し                   | 検索、エクスプローラ、タブ操作      |
| `Alt` (Shell)                       | CLI 補助操作                          | fzf/zoxide ウィジェット (`Q/D/T/R`) |

## 現在の適用状況

### デスクトップ（Omarchy 配列）

配置方針は `nix/home/keybindings/bindings.nix` に action とキーを一度だけ定義し、同じ home 配下で
macOS の AeroSpace、native NixOS の Hyprland、Windows の GlazeWM の設定を生成する。
`nix/hosts/` は OS のサービス・セッション有効化と競合解除に限定する。
責務・未対応の操作は [共通定義と OS 別実装](./omarchy.md) を参照。
WSL guest に Hyprland は導入しない。Windows は Windows キーを Super とし、GlazeWM で
デスクトップ全体の操作を扱う。Nix 生成済み設定を chezmoi で配布するため、Windows の適用時に Nix は不要。

macOS は nix-darwin の AeroSpace サービスで管理し、Super=Command とする。
⌘F・⌘T・⌘S・⌘数字・⌘Tab などはデスクトップ操作がアプリ標準キーより優先する。
配列、macOS での代替動作、初回権限設定と回復方法は
[Omarchy macOS](./omarchy-macos.md) を参照。native NixOS は Super キーを使い、
Hyprland セッションで動作する設定。Windows は [GlazeWM の運用と差異](./omarchy.md#windows-デスクトップの運用) を参照。
これらはターミナル内の prefix 契約とは別の層であり、各 OS の実際のキー入力は未検証。

### Terminals

WezTerm / Herdr の terminal Window Manager の共通 prefix は `Ctrl+Space`。prefix に続けて、次の共通 suffix を入力する。

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

| target  | Workspace | Tab  | Pane | Session |
| ------- | --------- | ---- | ---- | ------- |
| WezTerm | 対応      | 対応 | 対応 | 対応    |
| Herdr   | 対応      | 対応 | 対応 | 対応    |

- WezTerm は組み込み leader を使い、prefix timeout は1秒。
- Terminal.app は共通 prefix の対象外とし、標準のキー操作を使用する。デスクトップ全体の Omarchy 配列は AeroSpace、ターミナル内の共通操作は WezTerm の組み込み leader が担当するため、Terminal.app 専用の常駐 adapter は導入しない。
- Windows Terminal は共通 prefix の対象外とし、タブ・ペイン操作は標準のキー操作を使用する。常駐 adapter は導入しない。
- Herdr は native prefix/key table を使う。
- nested terminal では `Ctrl+Space Ctrl+Space` を押すと内側へ `Ctrl+Space` を1回だけ転送する。その後に共通 suffix を入力することで、内側の Herdr を操作できる。

Window Manager 契約外の操作は維持する。WezTerm の `Ctrl+Command+矢印` pane resize、macOS の `Command+Alt+H/L` window focus、Windows/Linux の `Alt+Shift+H/L` window focus と `Alt+Shift+矢印` pane resize、`Ctrl+Alt+W` pane zoom が該当する。WezTerm の `Shift+Enter` と Windows Terminal の `Shift+Enter` / `Ctrl+Enter` も複数行入力用として維持する。

- macOS の全アプリに `Ctrl+Command+M` を割り当て、標準メニューの `Zoom` または `拡大／縮小` を実行する。
- 設定反映後は対象アプリを再起動する。対象メニューを持たないアプリや、一部のElectronアプリでは動作しない場合がある。

### Editors

- Neovim
  - `Leader` は `Space`
  - `Ctrl+H/J/K/L`: Neovim 内の window 移動（Herdr の pane 移動は共通 prefix を使う）
  - `Ctrl+Z`: undo
  - `Ctrl+Y`: normal/visual は redo、insert は補完候補の確定
  - `-`: Oil エクスプローラ、`Space+e`: 診断表示
  - Oil 内: `Enter` で開く、`Ctrl+S` で縦分割、`Ctrl+H` で横分割、`Ctrl+T` で新規タブ、`Esc` で閉じる、`g.` で隠しファイル切替、`Ctrl+L` で再読み込み（Oil 内では window 移動より優先）
  - `gc/gcc`: 標準コメント、`grr/grn/gra/gri/grt`: 標準 LSP 操作
  - `Ctrl+X Ctrl+O`: LSP 補完、`Ctrl+X Ctrl+F`: パス補完、`Ctrl+N/P`: バッファ補完
  - `Tab/Shift+Tab`: 補完選択／snippet 移動、`Enter`: 選択候補の確定（未選択なら改行）
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
  - `Ctrl+.`: Sidekick focus、`Space+as/ad`: CLI 選択／close
  - `Space+at/af/av/ap`: Sidekick へ位置／ファイル／選択範囲送信／prompt 選択
  - `Space+du/dc/dd/dt`: Devcontainer up／コンテナ内 bash／down／toggle
  - Markdown のインライン表示切り替え: `Space+mp`（`render-markdown.nvim`）
  - Marp のブラウザプレビュー切り替え: `Space+marp`
  - 詳細・terminal prefix と補完の競合は [Neovim](./neovim.md) を参照

### Shells

- zsh
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Ctrl+T/R`・`Alt+C`: 標準 fzf ウィジェット（ファイル・履歴・ディレクトリ選択）
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
- zsh は標準 integration を使い、`Ctrl+T` でファイル選択、`Ctrl+R` で履歴検索、`Alt+C` でディレクトリ選択して `cd`
- Bash / PowerShell の `Alt+D` は `fd --absolute-path` + `fzf` でディレクトリ検索して `cd`
- Bash / PowerShell の `Alt+T` は `fd` + `fzf` でファイル/ディレクトリを選択してコマンドラインへ挿入
- Bash / PowerShell の `Alt+R` は履歴を `fzf` で選択してコマンドラインへ反映

## 運用ルール

- 新しいショートカットを追加する前に、この表のどのグループに属するかを先に決める
- terminal の Workspace/Tab/Pane/Session 操作は `Ctrl+Space` と共通 suffix を優先する
- target が持たない capability は no-op とし、target 固有の代替キーを共通契約へ混ぜない
- nested terminal の prefix 転送は `Ctrl+Space Ctrl+Space` に統一する
- WezTerm の直接 window focus / pane resize は共通契約外の補助操作として維持する
- Neovim など Unix/Vim 系は `Ctrl+H/J/K/L` を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
