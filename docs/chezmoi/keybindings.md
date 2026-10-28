# キーバインド統一方針

Nix で管理するデスクトップ・Ghostty・Neovim 配列と、chezmoi が配布する Windows / WSL 設定のキー設計方針。

## 目的

- コンテキストが変わっても同じ指の動きで操作できるようにする
- OS/IME と競合しやすいキーの利用範囲を狭くする
- `Vim` 拡張への依存を避け、標準機能ベースで運用する

## 統一ルール

| グループ                            | 役割                                  | 例                                  |
| ----------------------------------- | ------------------------------------- | ----------------------------------- |
| `Ctrl+Space`                        | WezTerm の追加操作 / Herdr prefix     | `Ctrl+Space` + suffix               |
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

配置方針は `nix/home/keybindings/` に共通 action とキーを定義し、macOS の AeroSpace と native NixOS の Hyprland 設定を生成する。Windows は標準ショートカットを使用し、グローバルなキーのリマップは行いません。WSL guest に Hyprland は導入しません。責務・OS ごとの代替動作は [共通定義と OS 別実装](./omarchy.md) を参照してください。

キー配列の正本は `nix/home/keybindings/bindings.nix` と、それが読み込む `nix/modules/terminals/ghostty/ghostty.nix` / `nix/modules/editors/nvim/neovim.nix` です。`task keybindings:export` がロック済み Nix 入力で正本を直接評価し、jq でコミット対象の `generated.json` を更新します。chezmoi は Ghostty / Neovim の export を NixOS-WSL の `~/.config/dotfiles/keybindings/` に配置します。Windows の apply は Nix を呼びません。WSL の Home Manager は export を読む loader を所有し、native Unix は同じ Nix 定義を直接読みます。Nix の単体テストは生成済み JSON と正本の一致を検査します。

Windows では `Super=Win` とし、同じキーの標準操作を remap で上書きします。`Win+D` は無効化します。Windows キーの全機能を無効化する `NoWinKeys` は使わず、`Win+L` や `Ctrl+Alt+Del` などの OS 予約操作は維持します。初回の loader 導入は `nrs`、以後の反映は `task chezmoi` です。[install.cmd と export の手順](./omarchy.md#export-と反映手順) を参照してください。

`Win+Shift+F` の Files は Nix が導入する NixOS-WSL の Nautilus を WSLg で起動します。Obsidian も Nix 側のアプリを起動し、Windows WinGet では導入しません。

配列の生成・配置テストと、各アプリでの実キー入力の確認は区別します。

WSLg Ghostty の resize はアプリ内の Ctrl+Alt+Shift 系キーに直接割り当てます。Windows のコピー・貼り付けとデスクトップ操作は標準キーを使います。

macOS は nix-darwin の AeroSpace サービスで管理し、Super=Command とする。
⌘F・⌘T・⌘S・⌘数字・⌘Tab などはデスクトップ操作がアプリ標準キーより優先する。
配列、macOS での代替動作、初回権限設定と回復方法は
[Omarchy macOS](./omarchy-macos.md) を参照。native NixOS は Super キーを使い、Hyprland セッションで動作します。これらはターミナル内の prefix 契約とは別の層です。

### Terminals

#### Ghostty

Ghostty は `ghostty.nix` の直接キー28割り当てを使います。macOS の標準 Command キー設定は残し、次の配列を追加します。WSL では export した `ghostty.conf` を読み込み、resize は `ghostty-wsl.nix` の Ctrl+Alt+Shift 系キーをアプリ内で直接処理します。

| キー                        | 操作                              |
| --------------------------- | --------------------------------- |
| `Ctrl+Shift+E`              | 上下に分割（新しい pane は下）    |
| `Ctrl+Shift+O`              | 左右に分割（新しい pane は右）    |
| `Ctrl+Alt+矢印`             | その方向の pane に移動            |
| `Super+Ctrl+Shift+矢印`     | その方向へ10ピクセルのサイズ変更  |
| `Super+Ctrl+Shift+Alt+矢印` | その方向へ100ピクセルのサイズ変更 |
| `Ctrl+Shift+T`              | 新しい tab                        |
| `Ctrl+Shift+Left/Up`        | 前の tab                          |
| `Ctrl+Shift+Right/Down`     | 次の tab                          |
| `Alt+1..9`                  | 指定した tab に移動               |

Ghostty の `resize_split` の単位はピクセルで、行数ではありません。反映後は Ghostty の設定を再読み込みします。

#### WezTerm

WezTerm は split / tab / pane 移動を Ghostty と同じ直接キーで操作する。Windows WezTerm のサイズ変更キーは WSL Ghostty 向け export と同じ transport chord を使う。サイズ変更の単位は Ghostty がピクセル、WezTerm がセルなので、WezTerm は小幅を1セル、大幅を10セルとして近い操作量にする。

| キー                                      | 操作                                                        |
| ----------------------------------------- | ----------------------------------------------------------- |
| `Ctrl+Shift+E`                            | 下に分割                                                    |
| `Ctrl+Shift+O`                            | 右に分割                                                    |
| `Ctrl+Shift+T`                            | 新しい tab                                                  |
| `Ctrl+Shift+Left/Up`                      | 前の tab                                                    |
| `Ctrl+Shift+Right/Down`                   | 次の tab                                                    |
| `Ctrl+Alt+矢印`                           | その方向の pane に移動                                      |
| `Ctrl+Alt+Shift+矢印`                     | WezTerm はその方向へ1セル、Ghostty は10ピクセルのサイズ変更 |
| `Ctrl+Alt+Shift+Home/PageDown/PageUp/End` | WezTerm は10セル、Ghostty は100ピクセルのサイズ変更         |
| `Alt+1..9`                                | 指定した tab に移動                                         |

`Ctrl+Space` は WezTerm 固有の workspace / session 操作と pane / tab を閉じる操作に残す。WezTerm は組み込み leader を使い、prefix timeout は1秒。

| suffix | 操作                            |
| ------ | ------------------------------- |
| `w`    | workspace picker                |
| `a`    | workspace を作成                |
| `q`    | tab を閉じる                    |
| `x`    | pane を閉じる                   |
| `g`    | workspace / tab / domain picker |
| `d`    | domain を detach                |
| `[`    | copy mode                       |
| `c`    | clipboard に copy               |

Terminal.app は WezTerm の組み込み leader を使わず、標準のキー操作を使用する。デスクトップ全体の Omarchy 配列は AeroSpace が担当するため、Terminal.app 専用の常駐 adapter は導入しない。

#### Herdr

Herdr は `Ctrl+Space` の terminal Window Manager prefix と native key table を使う。suffix は次のとおり。

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

- nested terminal では `Ctrl+Space Ctrl+Space` で内側へ prefix を1回転送し、その後の suffix で内側の Herdr を操作する。

Window Manager 契約外の WezTerm 操作として、pane resize、window focus、pane zoom を設定します。Windows の WezTerm は PowerShell を既定シェルにし、NixOS-WSL の起動は別の launcher profile から行います。

- macOS の全アプリに `Ctrl+Command+M` を割り当て、標準メニューの `Zoom` または `拡大／縮小` を実行する。
- 設定反映後は対象アプリを再起動する。対象メニューを持たないアプリや、一部のElectronアプリでは動作しない場合がある。

### Editors

- Neovim
  - `Leader` は `Space`
  - `Ctrl+H/J/K/L`: Neovim 内の window 移動（Herdr の pane 移動は共通 prefix を使う）
  - `Ctrl+Z`: undo
  - `Ctrl+Y`: normal/visual は redo、insert は補完候補の確定
  - `Space`: which-key のコマンド候補、`Space Space`: fuzzy file search
  - `Space e`: Oil サイドバー切り替え、`-`: 現在のディレクトリを Oil で開く
  - `Space g g`: Lazygit、`Space s g`: ファイル検索
  - `Ctrl+w w`: 次の window、`Ctrl+Left/Right`: Oil サイドバーの幅を2列ずつ変更（サイドバーがなければ現在の window）
  - `Shift+H/L`: 前 / 次の buffer、`Space b d`: buffer を閉じる
  - `Space d e`: 診断表示
  - Oil 内: `a` / `A` で現在の親ディレクトリにファイル / ディレクトリを追加、`d` で削除、`m` で移動先ディレクトリを指定、`r` で名前変更、`?` でキーのヘルプ。入力 prompt と Oil の確認・保存処理を使い、削除は trash に送る
  - Oil 内の補助操作: `Enter` で開く、`Ctrl+S` で縦分割、`Ctrl+H` で横分割、`Ctrl+T` で新規タブ、`Esc` で閉じる、`g.` で隠しファイル切替、`Ctrl+L` で再読み込み（Oil 内では window 移動より優先）
  - `gc/gcc`: 標準コメント、`grr/grn/gra/gri/grt`: 標準 LSP 操作
  - `Ctrl+X Ctrl+O`: LSP 補完、`Ctrl+X Ctrl+F`: パス補完、`Ctrl+N/P`: バッファ補完
  - `Tab/Shift+Tab`: 補完選択／snippet 移動、`Enter`: 選択候補の確定（未選択なら改行）
  - `Space+ff/fg/fb`: ファイル検索/grep/buffers
  - `Ctrl+.`: Sidekick focus、`Space+as/ad`: CLI 選択／close
  - `Space+at/af/av/ap`: Sidekick へ位置／ファイル／選択範囲送信／prompt 選択
  - `Space+du/dc/dd/dt`: Devcontainer up／コンテナ内 bash／down／toggle
  - Markdown のインライン表示切り替え: `Space+mp`（`render-markdown.nvim`）
  - Marp のブラウザプレビュー切り替え: `Space+marp`
  - 提示された共通17割り当ては `neovim.nix` が正本。反映後は Neovim を再起動する。補助機能・terminal prefix と補完の競合は [Neovim](./neovim.md) を参照

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
- Ghostty / WezTerm の split・tab・pane 移動は共通の直接キーを使う。WezTerm 固有操作は `Ctrl+Space`、Herdr は共通 suffix を使う
- target が持たない capability は no-op とし、target 固有の代替キーを共通契約へ混ぜない
- nested terminal の prefix 転送は `Ctrl+Space Ctrl+Space` に統一する
- WezTerm の直接 window focus / pane resize は共通契約外の補助操作として維持する
- Neovim など Unix/Vim 系は `Ctrl+H/J/K/L` を優先して維持する
- `Vim` 拡張前提の操作説明は追加しない
