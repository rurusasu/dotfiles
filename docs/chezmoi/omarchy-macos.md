# macOS: Omarchy のデスクトップキー配置

共通のキー割り当てを `nix/home/keybindings/bindings.nix` に置き、
`nix/home/keybindings/aerospace.nix` の純粋な関数で AeroSpace の設定へ変換する。
アプリ選択・起動コマンドは同ディレクトリの `darwin-commands.nix` が所有する。
`nix/hosts/darwin/omarchy-keybindings.nix` はサービス、macOS の既存ショートカットとの競合、
OS 固有の有効化を担当する。home 側の生成結果を通常の Nix import で受け取り、
nix-darwin の `services.aerospace` へ渡す。Home Manager 側で同じサービスを管理しない。
nix-darwin の `services.aerospace` が設定ファイルを
Nix store に生成し、launchd で起動する。chezmoi で AeroSpace 設定を配布しない。

パッケージの定義は `nix/packages/catalog/`、選択ロジックは `providers/`、公開入口は
`nix/packages/sets.nix` に置く。キー配列、OS ごとの実行方法、パッケージ配布は
変更理由が異なるため分割する。共通データを複製せず consumer の入口を保つ方針は
[パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照。
native NixOS、Windows デスクトップ、WSL の対応範囲は [共通定義と OS 別実装](./omarchy.md) を参照。

参照: [Omarchy のキー一覧](https://github.com/omacom/omarchy/blob/quattro/manual/07-hotkeys.md)、
[ウィンドウ操作の実装](https://github.com/omacom/omarchy/blob/quattro/default/hypr/bindings/tiling.lua)。
2026-09-28 に確認した quattro 配列を基準にする。Super=Command、Alt=Option。

## 標準キーの置き換え

以下は全アプリに優先する。たとえば ⌘F は検索、⌘T は新規タブ、⌘S は保存、
⌘Q はアプリ終了としては使えなくなる。アプリ固有操作にはメニューを使う。
⌘C/X/V は macOS 標準のままで Omarchy の共通クリップボード操作と一致する。

| キー                                    | 操作                                                         |
| --------------------------------------- | ------------------------------------------------------------ |
| ⌘Enter                                  | WezTerm 起動                                                 |
| ⌘Shift Enter / ⌘Shift B                 | Dia 起動                                                     |
| ⌘Shift F/O/A                            | Finder / Obsidian / ChatGPT                                  |
| ⌘Shift /                                | 1Password                                                    |
| ⌘Space / ⌘Option Space                  | Raycast                                                      |
| ⌘K                                      | このキー一覧                                                 |
| ⌘矢印                                   | 方向にあるウィンドウへフォーカス                             |
| ⌘Shift 矢印                             | 方向にあるウィンドウと入れ替え                               |
| ⌘Shift Option 矢印                      | ワークスペースを隣のモニターへ移動                           |
| ⌘1〜9 / ⌘0                              | ワークスペース 1〜9 / 10                                     |
| ⌘Shift 数字                             | ウィンドウを移動し、移動先へ切り替え                         |
| ⌘Shift Option 数字                      | ウィンドウだけ移動                                           |
| ⌘Tab / ⌘Shift Tab                       | 次 / 前のワークスペース                                      |
| ⌘Ctrl Tab                               | 直前のワークスペース                                         |
| Option Tab / Option Shift Tab           | 現在のワークスペース内で次 / 前のウィンドウ                  |
| Ctrl Option Tab / Ctrl Option Shift Tab | 次 / 前のモニター                                            |
| ⌘W / ⌘Q                                 | ウィンドウを閉じる（アプリ終了ではない）                     |
| ⌘T                                      | タイル / フローティング切り替え                              |
| ⌘J                                      | 分割方向を切り替え                                           |
| ⌘F / ⌘Ctrl F                            | 現在のワークスペース内で全画面切り替え                       |
| ⌘− / ⌘=                                 | 幅を 100px 縮小 / 拡大                                       |
| ⌘Shift − / ⌘Shift =                     | 高さを 100px 縮小 / 拡大                                     |
| 上記サイズ変更に Option / Ctrl を追加   | 25px / 300px 単位                                            |
| ⌘G / ⌘Option G                          | accordion 切り替え / tiles に戻す                            |
| ⌘Option 矢印                            | 隣のウィンドウと同じコンテナにまとめる                       |
| ⌘S / ⌘grave                             | scratchpad ワークスペースと直前のワークスペースを往復        |
| ⌘Option S / ⌘Shift grave                | ウィンドウを scratchpad へ移動                               |
| ⌘Ctrl C/Q/T                             | Screenshot / Calculator / Activity Monitor                   |
| ⌘Ctrl L                                 | 画面ロック（Raycast）                                        |
| ⌘Ctrl V/E                               | クリップボード履歴 / 絵文字（Raycast）                       |
| ⌘Ctrl A/B/D/W/P                         | サウンド / Bluetooth / ディスプレイ / Wi-Fi / バッテリー設定 |
| ⌘Ctrl Option Escape                     | キーの横取りを一時停止 / 再開                                |

Spotlight、ウィンドウ巡回、⌘Shift 数字のスクリーンショットの競合を
nix-darwin activation で無効化する。他のシステムショートカットの設定は保持する。
Raycast などでユーザーが追加したグローバルキーは別途競合確認が必要。

## macOS での差異

これは Omarchy のデスクトップキー配置の移植であり、Hyprland 自体の移植ではない。
AeroSpace の仮想ワークスペースを使う。macOS の Mission Control Spaces とは別物。
scratchpad はオーバーレイではなく専用ワークスペース、group は accordion で代替する。
⌘Tab / ⌘Shift Tab は全モニター共通の 1〜10 を数値順に巡回し、空 workspace も含める。
scratchpad は巡回対象から除外し、その状態から次へ進むと 1、前へ戻ると 10 に移る。
サイズ変更は AeroSpace の幅・高さ基準であり Hyprland の境界移動とは異なる。

Hyprland の scrolling/dwindle 切り替え、pseudo、sticky、透明度、マウス修飾ドラッグ、
通知・テーマ・バー操作、Linux 専用アプリは未移植。これらのキーを別操作へ偽装しない。
ターミナル内の共通 Ctrl+Space 契約とエディタ設定は別の層として維持する。

## 反映と検証

確認済みの範囲は設定のビルドとパーサー検査です。nix-darwin の実機反映、Accessibility 許可、実際のキー入力は未検証です。

通常は `nrs` で適用する。ブランチから適用する場合は対象 checkout 内で
`DOTFILES_SKIP_FLAKE_UPDATE=1 ./install.sh` を使う。
初回はシステム設定 → プライバシーとセキュリティ → アクセシビリティで
AeroSpace を許可する。この許可は nix-darwin では付与できない。
システムショートカットの無効化が反映されない場合はログアウト・ログインする。

```sh
aerospace reload-config --dry-run
aerospace list-workspaces --all
launchctl print gui/$(id -u)/org.nixos.aerospace
```

実際のキー入力で ⌘Enter、⌘F、⌘T、⌘1/2、⌘Shift 2、⌘Tab を確認する。
キー一覧・設定検査の成功だけでは macOS によるキー横取りや Accessibility 許可を検証できない。
回復時は ⌘Ctrl Option Escape、または `aerospace mode passthrough` を使う。
完全に無効化する場合は `services.aerospace.enable = lib.mkForce false` を宣言して再反映する。
無効化中は標準ショートカットの無効化処理と専用 Dock 設定も生成しない。
無効化した macOS システムショートカットはシステム設定から必要に応じて再度有効にする。
