# Omarchy 配列の共通定義と OS 別実装

## 配置方針

共通キー配置とユーザー設定は `nix/home/keybindings/`、OS のサービス・セッション有効化と競合解除は `nix/hosts/<host>/` に分けます。共通定義から Darwin、native NixOS、Windows のデスクトップ設定を生成します。OS への適用と実機検証は Nix 評価・ビルドとは別の確認事項です。

キー割り当ては `bindings.nix` の action、key、modifier を正本とし、同じ操作のキーを OS ごとに複製しません。アプリの選択・起動などユーザー設定は home 側に置き、OS のロックやシステム設定画面など host 統合が必要なコマンドは host から渡せる構成にします。

| 層                        | 編集先                                                             | 責務                                                                 |
| ------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| キー割り当て              | `nix/home/keybindings/bindings.nix`                                | action とキーの単一定義、重複キーの検出                              |
| macOS 設定生成            | `nix/home/keybindings/aerospace.nix`                               | 共通 action を AeroSpace の binding へ変換する純粋な関数             |
| macOS アプリ・補助操作    | `nix/home/keybindings/darwin-commands.nix`, `aerospace-cycle.nix`  | ユーザーのアプリ選択と数値順 workspace 巡回。OS サービスを所有しない |
| native NixOS 設定生成     | `nix/home/keybindings/hyprland-renderer.nix`                       | 共通 action を Hyprland Lua へ変換する純粋な関数                     |
| native NixOS ユーザー設定 | `nix/home/keybindings/hyprland.nix`                                | Lua 設定を配置する Home Manager module                               |
| Windows 設定生成          | `nix/home/keybindings/glazewm.nix`                                 | 共通 action を GlazeWM の binding へ変換する純粋な関数               |
| Windows アプリ・補助操作  | `nix/home/keybindings/glazewm-commands.nix`, `windows-actions.ps1` | アプリ選択・起動、Windows の標準パネル                               |
| macOS host                | `nix/hosts/darwin/omarchy-keybindings.nix`                         | AeroSpace サービスと macOS shortcut の競合処理                       |
| native NixOS host         | `nix/hosts/linux/omarchy-keybindings.nix`                          | Hyprland セッション有効化と home 側 module の選択                    |
| Windows host              | `nix/hosts/windows/omarchy-keybindings.nix`, `start-glazewm.ps1`   | 設定出力の合成、GlazeWM の起動と既存プロセスの確認                   |
| package/provider          | `nix/packages/catalog/`                                            | アプリと compositor の配布 metadata                                  |

キー配置は OS をまたぐ個人設定であり、特定 host や package の配布定義には属しません。一方、セッションやサービスの有効化は OS 側の責務です。この変更理由の違いで分割し、新しいトップレベルのディレクトリを増やさず既存の home/hosts 境界を使います。SSOT は各定義を一度だけ持つことであり、1 ファイルへの集約ではありません。package データ・provider 選択・配布 metadata の共通ルールは [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

## 読み込みと設定の所有者

- Darwin host は `aerospace.nix` を通常の Nix `import` で呼び、生成結果を `services.aerospace.settings.mode.main.binding` に渡します。設定ファイルと launchd は nix-darwin が所有し、Home Manager や chezmoi で二重管理しません。
- native NixOS host は `programs.hyprland.enable` と Home Manager module の選択を担当します。`home/keybindings/hyprland.nix` が `configType = "lua"` を明示し、ユーザー設定を配置します。
- Windows host は home の純粋な設定生成関数を通常の Nix `import` で呼び、`config`、`supported`、`unsupported`、`artifacts` を公開します。`windows-keybindings-export` から生成した成果物をリポジトリ内の chezmoi source に保持し、Windows では chezmoi が配布します。生成物は直接編集せず、正本を変更して `task keybindings:export` で更新し、`task keybindings:check` で差分を検査します。
- `nix/home/linux.nix` は standalone Home Manager にも使われます。Hyprland module を無条件に読み込まず、native host のみが選択します。
- home 配下でも、共通データと純粋な設定生成関数は Home Manager module ではありません。これらを module の `imports` に渡しません。

## 対象範囲と実装状況

| 環境                          | デスクトップ層 | Super              | 有効化の境界                                                      |
| ----------------------------- | -------------- | ------------------ | ----------------------------------------------------------------- |
| macOS                         | AeroSpace      | Command            | nix-darwin のサービス。Accessibility は実機で許可が必要           |
| native NixOS                  | Hyprland       | Super/Windows キー | native Linux host のみで有効化。実機検証は未実施                  |
| Windows                       | GlazeWM        | Windows キー       | Windows host のデスクトップ全体。chezmoi で配布。実機検証は未実施 |
| NixOS-WSL                     | host が担当    | Windows キー       | guest に compositor を導入せず、Windows host の GlazeWM を使用    |
| standalone Linux Home Manager | 自動導入なし   | —                  | package set を使うだけでは desktop session を変更しない           |

native desktop の Hyprland/fuzzel/Firefox/Nautilus は `nix/packages/catalog/native-desktop.nix` に定義し、`WithDesktop` で選択します。`sets.all` は全 feature を含む既存契約を維持するため、standalone/WSL の Home Manager consumer は `nativeDesktopPackageNames` を明示的に除外します。native host は compositor をシステム側で選択し、home 側はユーザー向けアプリを選択します。

native NixOS では window/workspace 操作と terminal/browser/files/notes/AI/passwords/launcher/help/activity の起動を生成します。capture、calculator、lock、clipboard、emoji、audio、bluetooth、display、network、power、passthrough は未対応です。対応する実装なしにキーを割り当てないため、macOS と完全同等ではありません。既存の display manager は変更せず、Hyprland セッションを選択するか TTY から `Hyprland` を起動します。

主な共通操作は Super+Enter のターミナル起動、Super+矢印のウィンドウ移動、Super+数字の workspace 切り替え、Super+Shift+数字の移動、Super+Tab の次 workspace、Super+F の全画面、Super+T の floating 切り替えです。OS の機能が異なる場合、renderer は対応できる action のみ生成し、未対応 action を `unsupported` として公開します。共通定義にあることだけで、その OS で動作するとはみなしません。

macOS の全キー、標準 shortcut への影響、初回権限設定と回復方法は [macOS の運用](./omarchy-macos.md) を参照してください。AeroSpace の scratchpad は専用 workspace、group は accordion で代替します。Hyprland と挙動が同じになる保証はありません。

## Windows デスクトップの運用

GlazeWM は Windows デスクトップ全体を対象にします。Super は左右の Windows キーに展開します。
生成済みの `config.json`、`actions.ps1`、`start-glazewm.ps1`、`keybindings.txt` は
`~/.glzr/glazewm/` へ chezmoi で配置し、Startup の `Dotfiles GlazeWM.lnk` が起動処理を呼びます。
Windows で設定を適用する際に Nix は不要です。GlazeWM 自体は package catalog の Windows provider で導入します。

対応する操作は workspace 1〜10 の切り替え・移動・移動後の追従・次/前/直前への巡回、方向フォーカス、
幅/高さのサイズ変更、ウィンドウを閉じる、floating、分割方向、
全画面と最大化、キー捕捉の pause/resume です。空 workspace も 1〜10 の巡回対象に含めます。
ターミナルは WezTerm、ブラウザーは既定アプリ、files は Explorer を起動します。
Obsidian、ChatGPT、1Password、Start launcher、ローカルのキー一覧、画面切り取り、電卓、
Task Manager、画面ロック、クリップボード履歴、絵文字パネル、各設定画面の起動も生成します。
ChatGPT は既定ブラウザーで `https://chatgpt.com/` を開きます。
Start・クリップボード・絵文字の標準パネルは、押した修飾キーを離してから開きます。

group/ungroup/join、scratchpad、隣のウィンドウとの厳密な方向入れ替え、モニター巡回、
フォーカス中のウィンドウを方向指定で別モニターへ送る操作は未対応です。
Alt+Tab / Alt+Shift+Tab は Windows 標準のウィンドウ巡回を使い、GlazeWM のキーとして登録しません。
全画面と最大化は異なる Windows の状態であり、Hyprland の tiled fullscreen と同一ではありません。

[GlazeWM 公式ドキュメント](https://github.com/glzr-io/glazewm#config-documentation) の既定設定名は
`config.yaml` ですが、この管理設定は JSON として出力した `config.json` を `start --config` で明示します。
JSON は GlazeWM の YAML パーサーでも読み込める形式です。Windows が予約する一部のキー（公式の例は Win+L）は捕捉できない場合があります。
共通配列の画面ロックは Win+Ctrl+L であり、Win+L の予約を理由にこの操作を未対応とはしません。
キー捕捉と他の常駐アプリとの競合は実機で確認が必要です。

```powershell
dotf chezmoi
& "$HOME\.glzr\glazewm\start-glazewm.ps1" -Check
& "$HOME\.glzr\glazewm\start-glazewm.ps1"
glazewm query workspaces
```

`-Check` は配置された `config.json` の workspace とキー重複を検査し、起動しません。
GlazeWM のコマンド・キー構文は起動または再読み込み時に検査されます。
起動処理は同じ Windows セッション内の実行ファイルと設定パスを確認し、一致するプロセスの設定だけを再読み込みします。他の設定で起動中の GlazeWM は停止・上書きせず、
エラーとして返します。自分でそのプロセスを終了してから起動処理を再実行してください。
session 0、非対話環境、GitHub Actions では Startup shortcut の作成までを行い、GlazeWM の起動は対話ログインまで延期します。
一時停止/再開は Win+Ctrl+Alt+Escape を使います。
実際のキー入力、Windows 予約キーの挙動、Startup からの起動は未検証です。

## ターミナルとの境界と検証

デスクトップ配列は各 OS の window manager が扱います。ターミナル内の pane/tab/session 操作は、[キーバインド統一方針](./keybindings.md) の `Ctrl+Space` 契約を維持します。WSL のターミナル操作と Windows host の GlazeWM は独立した層です。

Nix の検証では共通キーの重複、renderer の出力、host import の境界を確認します。実機では対象セッションで端末起動、方向移動、workspace 切り替えと移動、floating、全画面をキー入力で確認します。Nix 評価や設定生成の成功だけでは compositor の起動、macOS の Accessibility、Windows host のグローバルキー捕捉は確認できません。

`nix build .#checks.aarch64-darwin.aerospace-workspace-cycle` は生成した巡回スクリプトを実行し、1〜10 の順序、scratchpad の除外、CLI エラーの伝播を検証します。これは CLI 境界の検証であり、macOS の実キー入力テストを置き換えません。
