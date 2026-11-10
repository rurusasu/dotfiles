# キーバインド統一方針

Nix で管理するデスクトップ・Ghostty・Herdr・Neovim と、chezmoi が配布する Windows / WSL 設定のキー設計方針。

## 目的

- コンテキストが変わっても同じ指の動きで操作できるようにする
- OS/IME と競合しやすいキーの利用範囲を狭くする
- `Vim` 拡張への依存を避け、標準機能ベースで運用する

## 統一ルール

`Super` は macOS では `Command`、Linux / WSL では Windows（Super）キーを指します。`Ctrl` は各 OS の Control キーのままで、`Super` へ自動変換しません。Herdr の prefix は Omarchy と同じ `Ctrl+Space` で、デスクトップの `Super` とは別です。

| グループ                 | 役割                                | 例                                  |
| ------------------------ | ----------------------------------- | ----------------------------------- |
| `Ctrl+Space`             | Herdr prefix                        | `Ctrl+Space` + suffix               |
| `Ctrl+Space Ctrl+Space`  | nested terminal へ prefix を1回転送 | `Ctrl+Space Ctrl+Space` + suffix    |
| `Ctrl+Command+M` (macOS) | GUI window zoom / restore           | `Ctrl+Command+M`                    |
| `Ctrl`                   | Unix/Vim focus                      | `Ctrl+H/J/K/L`                      |
| `Shift+Enter`            | 複数行入力                          | AI CLI / terminal prompt 改行       |
| `Space` (`Leader`)       | editor 機能呼び出し                 | 検索、エクスプローラ、タブ操作      |
| `Alt` (Shell)            | CLI 補助操作                        | fzf/zoxide ウィジェット (`Q/D/T/R`) |

## 現在の適用状況

### デスクトップ（Omarchy 配列）

配置方針は `nix/home/keybindings/` に共通 action とキーを定義し、macOS の AeroSpace と native NixOS の Hyprland 設定を生成する。Windows は標準ショートカットを使用し、WSL 端末部分では Win キーを Super 入力として転送します。WSL guest に Hyprland は導入しません。対象範囲は [共通定義と OS 別実装](./omarchy.md) を参照してください。

デスクトップのキー配列は `nix/home/keybindings/bindings.nix`、Neovim のキー配列と leader は `nix/modules/editors/nvim/default.nix` が管理します。NixOS-WSL を含むすべての Unix 環境で、各アプリの Home Manager module が Nix 定義からキー設定を直接生成します。WSL の Neovim・Ghostty・Herdr のキー変更は `./install.sh` で反映し、アプリを再起動します。Windows の chezmoi は WSL へのキー設定配布を行いません。`task keybindings:export` は Windows 用の外観設定 `chezmoi/appearance/appearance.json` だけを更新します。

配列の生成・配置テストと、各アプリでの実キー入力の確認は区別します。

Windows のコピー・貼り付けとデスクトップ操作は標準キーを使います。

macOS は nix-darwin の AeroSpace サービスで管理し、Super=Command とする。
⌘F・⌘T・⌘S・⌘数字・⌘Tab などはデスクトップ操作がアプリ標準キーより優先する。
配列、macOS での代替動作、初回権限設定と回復方法は
[Omarchy macOS](./omarchy-macos.md) を参照。native NixOS は Super キーを使い、Hyprland セッションで動作します。これらはターミナル内の prefix 契約とは別の層です。

### Terminals

#### Windows Terminal

タブ・ペインの操作は Windows Terminal の標準ショートカットを使います。PowerShell 7 を既定プロファイルとし、NixOS-WSL は自動生成される `NixOS` プロファイルから起動します。

#### Ghostty

Ghostty の設定は macOS / Linux / WSL とも `nix/modules/terminals/ghostty/default.nix` の Home Manager module が管理します。既定キーを `keybind = clear` でクリアし、コピー・貼り付け、フォント、検索・スクロール、設定、新規ウィンドウ、全画面のキーだけを定義します。

Ghostty の分割・タブ作成・ペイン移動・サイズ変更・undo / redo にはキーを割り当てません。ターミナル内のタブ・ペイン・セッションは Herdr で操作します。

#### Herdr

Herdr は [Omarchy 公式の配列](https://github.com/omacom/omarchy/blob/quattro/config/herdr/config.toml) を使います。`omarchy` input の revision を `flake.lock` で固定し、その `[keys]` を `programs.herdr.settings.keys` から生成します。以下の `prefix` は `Ctrl+Space` です。

| 対象      | キー                                | 操作                    |
| --------- | ----------------------------------- | ----------------------- |
| Workspace | `prefix+w`                          | picker を開く           |
| Workspace | `prefix+Shift+C`                    | 新規作成                |
| Workspace | `↑` / `↓`                           | picker 内で前 / 次      |
| Workspace | `prefix+Shift+P` / `prefix+Shift+N` | 前 / 次                 |
| Tab       | `prefix+c`                          | 新規作成                |
| Tab       | `prefix+k`                          | 閉じる                  |
| Tab       | `prefix+p` / `prefix+n`             | 前 / 次                 |
| Pane      | `Ctrl+Alt+←/↓/↑/→`                  | 左 / 下 / 上 / 右へ移動 |
| Pane      | `prefix+v` / `prefix+h`             | 左右 / 上下分割         |
| Pane      | `prefix+x`                          | 閉じる                  |
| Session   | `prefix+g`                          | navigator を開く        |
| Session   | `prefix+d`                          | detach                  |
| Config    | `prefix+q`                          | 再読み込み              |

- nested terminal では `Ctrl+Space Ctrl+Space` で内側へ prefix を1回転送し、その後の suffix で内側の Herdr を操作する。

### GUI window zoom

- macOS の全アプリに `Ctrl+Command+M` を割り当て、標準メニューの `Zoom` または `拡大／縮小` を実行する。
- 設定反映後は対象アプリを再起動する。対象メニューを持たないアプリや、一部のElectronアプリでは動作しない場合がある。

### Editors

- Neovim
  - `Leader` は `Space`
  - `Ctrl+H/J/K/L`: Neovim 内の window 移動（Herdr の pane 移動は `Ctrl+Alt+矢印` を使う）
  - `Ctrl+Z`: undo
  - `Ctrl+Y`: normal/visual は redo、insert は補完候補の確定
  - `Space`: which-key のコマンド候補、`Space Space`: fuzzy file search
  - `-`: 現在のファイルの親ディレクトリを Oil で開く
  - `Space g g`: Lazygit、`Space s g`: ファイル検索
  - `Ctrl+w w`: 次の window、`Ctrl+Left/Right`: 現在の window の幅を2列ずつ変更
  - `Shift+H/L`: 前 / 次の buffer、`Space b d`: buffer を閉じる
  - `Space d e`: 診断表示
  - Oil 内: 標準のバッファ編集で名前を追加・変更、行を削除・移動し、`:w` で反映する。ディレクトリ追加は名前の末尾に `/` を付け、削除は trash に送る
  - Oil の標準キー: `Ctrl+S` で縦分割、`Ctrl+H` で横分割、`Ctrl+T` で新規タブ、`Ctrl+C` で閉じる、`g?` でヘルプ、`g.` で隠しファイル切替、`Ctrl+L` で再読み込み（Oil 内では window 移動より優先）
  - Oil 内の `Esc` にも標準の `actions.close` を割り当てる
  - `gc/gcc`: 標準コメント、`grr/grn/gra/gri/grt`: 標準 LSP 操作
  - `Ctrl+X Ctrl+O`: LSP 補完、`Ctrl+X Ctrl+F`: パス補完、`Ctrl+N/P`: バッファ補完
  - `Tab/Shift+Tab`: 補完選択／snippet 移動、`Enter`: 選択候補の確定（未選択なら改行）
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
  - `Ctrl+.`: Sidekick focus、`Space+as/ad`: CLI 選択／close
  - `Space+at/af/av/ap`: Sidekick へ位置／ファイル／選択範囲送信／prompt 選択
  - `Space d c`: Lazydocker をフローティングターミナルで開閉（Podman に接続）
  - Markdown のインライン表示切り替え: `Space+mp`（`render-markdown.nvim`）
  - Marp のブラウザプレビュー切り替え: `Space+marp`
  - 共通キー配列は `neovim.nix` が正本。反映後は Neovim を再起動する。補助機能・terminal prefix と補完の競合は [Neovim](./neovim.md) を参照

### Shells

- zsh
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Ctrl+T/R`・`Alt+C`: 標準 fzf ウィジェット（ファイル・履歴・ディレクトリ選択）
- bash
  - zoxide の標準 `cd` / `cdi` を使い、fzf のキー連携は無効
- PowerShell
  - `Shift+Enter`: PSReadLine `AddLine`
  - `Alt+Q`: zoxide interactive jump (`zoxide query -i`)
  - `Alt+D/T/R`: fzf ウィジェット (PSReadLine)

### AI CLI

- Claude Code / Codex / terminal 内 AI prompt の複数行入力は `Shift+Enter` に統一する。
- `Ctrl+J` は押下キーとして使わない。Codex では LF を送る terminal の受信互換としてのみ許可する。

### zoxide + fzf integration

- `Alt+Q` は zsh / PowerShell で `zoxide query -i` を呼び出し、履歴ベースのディレクトリ候補をインタラクティブ選択する
- zsh は標準 integration を使い、`Ctrl+T` でファイル選択、`Ctrl+R` で履歴検索、`Alt+C` でディレクトリ選択して `cd`
- PowerShell の `Alt+D` は `fd --absolute-path` + `fzf` でディレクトリ検索して `cd`
- PowerShell の `Alt+T` は `fd` + `fzf` でファイル/ディレクトリを選択してコマンドラインへ挿入
- PowerShell の `Alt+R` は履歴を `fzf` で選択してコマンドラインへ反映

## 運用ルール

- 新しいショートカットを追加する前に、この表のどのグループに属するかを先に決める
- Windows Terminal は標準ショートカットを使う
- Ghostty はホスト端末として使い、ターミナル内のタブ・ペイン・セッション操作は Herdr の `Ctrl+Space` prefix に統一する
- target が持たない capability は no-op とし、target 固有の代替キーを共通契約へ混ぜない
- nested terminal の prefix 転送は `Ctrl+Space Ctrl+Space` に統一する
- Neovim など Unix/Vim 系は `Ctrl+H/J/K/L` を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
