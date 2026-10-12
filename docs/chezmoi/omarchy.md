# デスクトップキー設定の所有範囲

共通キー設定とユーザー設定は `nix/home/keybindings/`、OS service と有効化は `nix/hosts/<system>/<environment>/` が所有します。macOS は AeroSpace、native NixOS は Hyprland を使います。NixOS-WSL には compositor を導入しません。

Windows 用 GlazeWM の設定生成・配布機能は削除しました。Windows デスクトップのキー配列はこの repository では管理しません。WezTerm の pane、tab、launcher 操作は WezTerm 設定の責務です。

## WezTerm の境界

Windows の WezTerm 設定は chezmoi の `terminals/wezterm/wezterm.lua` に置きます。PowerShell を既定シェルとし、NixOS-WSL は別の launcher profile から起動します。Unix の設定は Home Manager が管理します。

Nix のテストは純粋な設定生成と実効値を検査します。実機の compositor 動作やキー入力は対象 host 上で確認します。

キー配置は OS をまたぐ個人設定であり、特定 host や package の配布定義には属しません。一方、セッションやサービスの有効化は OS 側の責務です。この変更理由の違いで分割し、新しいトップレベルのディレクトリを増やさず既存の home/hosts 境界を使います。SSOT は各定義を一度だけ持つことであり、1 ファイルへの集約ではありません。Unix module と Windows manifest の共通ルールは [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

## 読み込みと設定の所有者

- Darwin host は `aerospace.nix` を通常の Nix `import` で呼び、生成結果を `services.aerospace.settings.mode.main.binding` に渡します。設定ファイルと launchd は nix-darwin が所有し、Home Manager や chezmoi で二重管理しません。
- native NixOS host は `programs.hyprland.enable` と Home Manager module の選択を担当します。`home/keybindings/hyprland.nix` が `configType = "lua"` を明示し、ユーザー設定を配置します。
- `nix/hosts/shared/linux-home.nix` は standalone Home Manager にも使われます。Hyprland module を無条件に読み込まず、native host のみが選択します。
- home 配下でも、共通データと純粋な設定生成関数は Home Manager module ではありません。これらを module の `imports` に渡しません。

## 対象範囲と実装状況

| 環境                          | デスクトップ層   | Super              | 有効化の境界                                              |
| ----------------------------- | ---------------- | ------------------ | --------------------------------------------------------- |
| macOS                         | AeroSpace        | Command            | nix-darwin のサービス。Accessibility は実機で許可が必要   |
| native NixOS                  | Hyprland         | Super/Windows キー | native Linux host のみで有効化。実機検証は未実施          |
| Windows                       | 標準デスクトップ | Windows キー       | GlazeWM / AutoHotkey の導入・設定配布は行わない           |
| NixOS-WSL                     | host が担当      | Windows キー       | guest に compositor を導入せず、Windows host の構成に従う |
| standalone Linux Home Manager | 自動導入なし     | —                  | 共通 CLI module では desktop session を変更しない         |

GUI 導入は `nix/modules/tools.nix` にまとめます。Linux / WSLg の Chrome / Obsidian は `linuxDesktop`、Darwin の Dia は `darwin`、native desktop の Firefox / fuzzel / Nautilus は `nativeDesktop` に定義し、対応する host が選択します。ユーザー設定は `nix/home/keybindings/hyprland.nix` が管理します。Hyprland のセッションは native NixOS host がシステム側で有効化します。standalone / WSL には compositor を自動導入しません。

native NixOS では window/workspace 操作と terminal/browser/files/notes/AI/passwords/launcher/help/activity の起動を生成します。capture、calculator、lock、clipboard、emoji、audio、bluetooth、display、network、power、passthrough は未対応です。対応する実装なしにキーを割り当てないため、macOS と完全同等ではありません。既存の display manager は変更せず、Hyprland セッションを選択するか TTY から `Hyprland` を起動します。

native NixOS の AI キーは公式 Linux 版の `chatgpt` アプリを起動します。アプリと同梱 Codex CLI は Home Manager が導入し、WSL には Linux GUI を配布しません。

主な共通操作は Super+Enter のターミナル起動、Super+矢印のウィンドウ移動、Super+数字の workspace 切り替え、Super+Shift+数字の移動、Super+Tab の次 workspace、Super+F の全画面、Super+T の floating 切り替えです。OS の機能が異なる場合、renderer は対応できる action のみ生成し、未対応 action を `unsupported` として公開します。共通定義にあることだけで、その OS で動作するとはみなしません。

macOS の全キー、標準 shortcut への影響、初回権限設定と回復方法は [macOS の運用](./omarchy-macos.md) を参照してください。AeroSpace の scratchpad は専用 workspace、group は accordion で代替します。Hyprland と挙動が同じになる保証はありません。

## Windows デスクトップの運用

Windows は標準デスクトップを使用し、GlazeWM / Zebar / AutoHotkey を導入・起動しません。未使用の Nix export、renderer、生成物と Startup スクリプトは廃止しました。以前配置した Startup shortcut と実行中プロセスは自動削除・停止しません。

## ターミナルとの境界と検証

デスクトップ配列は各 OS の window manager が扱います。ターミナル内の pane/tab/session 操作は、[キーバインド統一方針](./keybindings.md) の `Ctrl+Space` 契約を維持します。WSL のターミナル操作は Windows の標準デスクトップ操作から独立した層です。

Nix の検証では共通キーの重複、renderer の出力、host import の境界を確認します。実機では対象セッションで端末起動、方向移動、workspace 切り替えと移動、floating、全画面をキー入力で確認します。Nix 評価や設定生成の成功だけでは compositor の起動、macOS の Accessibilityは確認できません。

`nix build .#checks.aarch64-darwin.aerospace-workspace-cycle` は生成した巡回スクリプトを実行し、1〜10 の順序、scratchpad の除外、CLI エラーの伝播を検証します。これは CLI 境界の検証であり、macOS の実キー入力テストを置き換えません。
