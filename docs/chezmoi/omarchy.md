# デスクトップキー設定の所有範囲

共通キー配列は `nix/home/keybindings/`、アプリの設定・サービスは `nix/modules/`、OS 別選択は `nix/defaults.nix:systemDefaults` が所有します。macOS は AeroSpace、native NixOS は Hyprland を使います。NixOS-WSL には compositor を導入しません。

Windows は標準デスクトップと標準ショートカットを使用し、共通デスクトップキーのリマップは行いません。Ghostty と Neovim のアプリ内キーは Nix の定義から生成し、chezmoi が export を WSL に配布します。

## ターミナルの境界

Windows Terminal の設定は chezmoi が管理します。PowerShell 7 を既定プロファイルとし、NixOS-WSL は Windows Terminal が自動生成する `NixOS` プロファイルから起動します。Ghostty と WezTerm の Unix 設定は Home Manager が管理します。

Nix のテストは純粋な設定生成と実効値を検査します。実機の compositor 動作やキー入力は対象 host 上で確認します。

キー配置は OS をまたぐ個人設定であり、特定 host や package の配布定義には属しません。一方、セッションやサービスの有効化は OS 側の責務です。この変更理由の違いで分割し、新しいトップレベルのディレクトリを増やさず既存の home/hosts 境界を使います。SSOT は各定義を一度だけ持つことであり、1 ファイルへの集約ではありません。Unix module と Windows manifest の共通ルールは [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

## 読み込みと設定の所有者

- `nix/modules/aerospace/default.nix` は `aerospace.nix` を通常の Nix `import` で呼び、生成結果を `programs.aerospace.settings.mode.main.binding` に渡します。設定ファイルと launchd は Home Manager が所有します。
- native NixOS は `platform = "linux"` の `systemDefaults` がセッションと Home Manager を接続します。`nix/modules/hyprland/default.nix` が `configType = "lua"` を明示し、ユーザー設定を配置します。architecture は `system` 引数で選択します。
- native NixOS と standalone Linux は同じ Home Manager の `sharedModules` を使い、Hyprland の system 設定は native 構成だけが有効化します。
- 共通データと純粋な設定生成関数は Home Manager module ではありません。これらを module の `imports` に渡しません。

## 対象範囲と実装状況

| 環境                          | デスクトップ層   | Super              | 有効化の境界                                                      |
| ----------------------------- | ---------------- | ------------------ | ----------------------------------------------------------------- |
| macOS                         | AeroSpace        | Command            | Home Manager のユーザーサービス。Accessibility は実機で許可が必要 |
| native NixOS                  | Hyprland         | Super/Windows キー | native Linux host のみで有効化。実機検証は未実施                  |
| Windows                       | 標準デスクトップ | Windows キー       | Windows 標準キーを使用し、グローバルなリマップは導入しない        |
| NixOS-WSL                     | host が担当      | Windows キー       | guest に compositor を導入せず、Windows host の構成に従う         |
| standalone Linux Home Manager | 自動導入なし     | —                  | 共通 CLI module では desktop session を変更しない                 |

Unix GUI の導入・設定はアプリごとの Home Manager module が所有し、実 module の `default.nix` は自動検出し、共通・OS 別構成の型付き option で有効化します。Windows GUI の導入は `windows/winget/packages.json` が所有します。Hyprland のユーザー設定は `nix/modules/hyprland/default.nix` が管理します。Hyprland のセッションは `nix/defaults.nix` の native Linux 設定で有効化します。standalone / WSL には compositor を自動導入しません。

native NixOS では window/workspace 操作と terminal/browser/files/notes/AI/passwords/launcher/help/activity の起動を生成します。capture、calculator、lock、clipboard、emoji、audio、bluetooth、display、network、power、passthrough は未対応です。対応する実装なしにキーを割り当てないため、macOS と完全同等ではありません。既存の display manager は変更せず、Hyprland セッションを選択するか TTY から `Hyprland` を起動します。

native NixOS の AI キーは公式 Linux 版の `chatgpt` アプリを起動します。アプリと同梱 Codex CLI は Home Manager が導入し、WSL には Linux GUI を配布しません。

主な共通操作は Super+Enter のターミナル起動、Super+矢印のウィンドウ移動、Super+数字の workspace 切り替え、Super+Shift+数字の移動、Super+Tab の次 workspace、Super+F の全画面、Super+T の floating 切り替えです。OS の機能が異なる場合、renderer は対応できる action のみ生成し、未対応 action を `unsupported` として公開します。共通定義にあることだけで、その OS で動作するとはみなしません。

macOS の全キー、標準 shortcut への影響、初回権限設定と回復方法は [macOS の運用](./omarchy-macos.md) を参照してください。AeroSpace の scratchpad は専用 workspace、group は accordion で代替します。Hyprland と挙動が同じになる保証はありません。

## Windows デスクトップの運用

アプリ起動やデスクトップ操作は Windows 標準の機能を使います。共通デスクトップ配列は macOS / native NixOS の renderer が扱い、Windows には配布しません。

## Export と反映手順

```powershell
task keybindings:export
task chezmoi
```

キーを変更した開発環境で `task keybindings:export` を実行し、正本の Nix ファイルと生成した JSON を一緒にコミットします。Windows での export は WSL の Nix を使います。chezmoi はコミット済み JSON を読み、Ghostty / Neovim の export を NixOS-WSL の `~/.config/dotfiles/keybindings/` にコピーします。chezmoi 実行時に Nix の評価・ビルドは行いません。GitHub Actions は export と Nix 定義の一致を検査し、自動生成・自動コミットは必要ありません。

通常の `install.cmd` は Windows GUI アプリの導入、NixOS-WSL の準備・同期、`nrs`、Windows chezmoi の順に実行します。`nrs` は `dotfiles.keybindings.fromWindowsExport` を有効にした WSL のアプリ loader を配置し、その後に chezmoi が export を配置します。既存環境でも loader 導入時は一度 `nrs` が必要です。以後のキー変更は export と `task chezmoi` で反映し、Neovim の再起動と Ghostty の設定再読み込みで読み込みます。native Unix のアプリは同じ Nix 定義を直接読みます。

## ターミナルとの境界と検証

デスクトップ配列は各 OS の desktop adapter が扱います。Windows Terminal は標準ショートカットを使います。Unix の Ghostty と WezTerm は split・tab・pane 移動に共通の直接キーを使い、WezTerm の固有操作と Herdr の操作には [キーバインド統一方針](./keybindings.md) の `Ctrl+Space` を使います。サイズ変更の単位は Ghostty がピクセル、WezTerm がセルです。

WSLg Ghostty は ghostty-wsl.nix が生成するアプリ内の直接キーを使います。10ピクセルの resize は Ctrl+Alt+Shift+矢印、100ピクセルは Ctrl+Alt+Shift+Home/PageDown/PageUp/End です。Windows 側のキー変換や常駐スクリプトは使いません。

Nix の検証では共通キーの重複、renderer の出力、host import の境界を確認します。実機では対象セッションで端末起動、方向移動、workspace 切り替えと移動、floating、全画面をキー入力で確認します。Nix 評価や設定生成の成功だけでは compositor の起動、macOS の Accessibilityは確認できません。

`nix build .#checks.aarch64-darwin.aerospace-workspace-cycle` は生成した巡回スクリプトを実行し、1〜10 の順序、scratchpad の除外、CLI エラーの伝播を検証します。これは CLI 境界の検証であり、macOS の実キー入力テストを置き換えません。
