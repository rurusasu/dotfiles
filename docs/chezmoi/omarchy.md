# デスクトップキー設定の所有範囲

共通キー配列は `nix/home/keybindings/`、アプリの設定・サービスは `nix/modules/`、OS 別選択は `nix/defaults.nix:systemDefaults` が所有します。macOS は AeroSpace、native NixOS は Hyprland を使います。NixOS-WSL には compositor を導入しません。

Windows は PowerToys Keyboard Manager を使い、提示された Omarchy 配列のアプリ起動、クリップボード、撮影、通知、外観、アイドル、ナイトモード、バー、音声出力操作を chezmoi で管理します。`Super=Win` です。キーの正本は `nix/home/keybindings/` に置き、デスクトップは `bindings.nix`、Ghostty は `ghostty.nix`、Neovim は `neovim.nix` が所有します。chezmoi は Nix が export した `generated.json` を読み、キー定義を別に持ちません。

Windows の設定更新は `scripts/powershell/Sync-PowerToysKeyboard.ps1`、操作の実行は `Invoke-DesktopAction.ps1` が担当します。Ghostty と Neovim は同じ export のアプリ設定を読みます。GlazeWM の設定生成・配布機能は削除しました。WezTerm の pane、tab、launcher 操作は WezTerm 設定の責務です。

## WezTerm の境界

Windows の WezTerm 設定は chezmoi の `terminals/wezterm/wezterm.lua` に置きます。PowerShell を既定シェルとし、NixOS-WSL は別の launcher profile から起動します。Unix の設定は Home Manager が管理します。

Nix のテストは純粋な設定生成と実効値を検査します。実機の compositor 動作やキー入力は対象 host 上で確認します。

キー配置は OS をまたぐ個人設定であり、特定 host や package の配布定義には属しません。一方、セッションやサービスの有効化は OS 側の責務です。この変更理由の違いで分割し、新しいトップレベルのディレクトリを増やさず既存の home/hosts 境界を使います。SSOT は各定義を一度だけ持つことであり、1 ファイルへの集約ではありません。Unix module と Windows manifest の共通ルールは [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

## 読み込みと設定の所有者

- `nix/modules/aerospace/default.nix` は `aerospace.nix` を通常の Nix `import` で呼び、生成結果を `programs.aerospace.settings.mode.main.binding` に渡します。設定ファイルと launchd は Home Manager が所有します。
- native NixOS は `platform = "linux"` の `systemDefaults` がセッションと Home Manager を接続します。`nix/modules/hyprland/default.nix` が `configType = "lua"` を明示し、ユーザー設定を配置します。architecture は `system` 引数で選択します。
- native NixOS と standalone Linux は同じ Home Manager の `sharedModules` を使い、Hyprland の system 設定は native 構成だけが有効化します。
- 共通データと純粋な設定生成関数は Home Manager module ではありません。これらを module の `imports` に渡しません。

## 対象範囲と実装状況

| 環境                          | デスクトップ層   | Super              | 有効化の境界                                                                  |
| ----------------------------- | ---------------- | ------------------ | ----------------------------------------------------------------------------- |
| macOS                         | AeroSpace        | Command            | Home Manager のユーザーサービス。Accessibility は実機で許可が必要             |
| native NixOS                  | Hyprland         | Super/Windows キー | native Linux host のみで有効化。実機検証は未実施                              |
| Windows                       | 標準デスクトップ | Windows キー       | PowerToys の Omarchy 配列を chezmoi で反映。GlazeWM / AutoHotkey は導入しない |
| NixOS-WSL                     | host が担当      | Windows キー       | guest に compositor を導入せず、Windows host の構成に従う                     |
| standalone Linux Home Manager | 自動導入なし     | —                  | 共通 CLI module では desktop session を変更しない                             |

Unix GUI の導入・設定はアプリごとの Home Manager module が所有し、実 module の `default.nix` は自動検出し、共通・OS 別構成の型付き option で有効化します。Windows GUI の導入は `windows/winget/packages.json` が所有します。Hyprland のユーザー設定は `nix/modules/hyprland/default.nix` が管理します。Hyprland のセッションは `nix/defaults.nix` の native Linux 設定で有効化します。standalone / WSL には compositor を自動導入しません。

native NixOS では window/workspace 操作と terminal/browser/files/notes/AI/passwords/launcher/help/activity の起動を生成します。capture、calculator、lock、clipboard、emoji、audio、bluetooth、display、network、power、passthrough は未対応です。対応する実装なしにキーを割り当てないため、macOS と完全同等ではありません。既存の display manager は変更せず、Hyprland セッションを選択するか TTY から `Hyprland` を起動します。

native NixOS の AI キーは公式 Linux 版の `chatgpt` アプリを起動します。アプリと同梱 Codex CLI は Home Manager が導入し、WSL には Linux GUI を配布しません。

主な共通操作は Super+Enter のターミナル起動、Super+矢印のウィンドウ移動、Super+数字の workspace 切り替え、Super+Shift+数字の移動、Super+Tab の次 workspace、Super+F の全画面、Super+T の floating 切り替えです。OS の機能が異なる場合、renderer は対応できる action のみ生成し、未対応 action を `unsupported` として公開します。共通定義にあることだけで、その OS で動作するとはみなしません。

macOS の全キー、標準 shortcut への影響、初回権限設定と回復方法は [macOS の運用](./omarchy-macos.md) を参照してください。AeroSpace の scratchpad は専用 workspace、group は accordion で代替します。Hyprland と挙動が同じになる保証はありません。

## Windows デスクトップの運用

Windows は標準デスクトップを使用します。PowerToys Keyboard Manager は export の Windows 向け38割り当てと `Win+D` の無効化を反映します。これには既存のブラウザ・Btop 起動キーの別名も含みます。必要なキーを完全一致の remap で上書きするため、同じキーの Windows 標準操作との競合を解除します。`NoWinKeys` による一括無効化は、Windows の操作を呼び出すためのキー送信にも影響するため使いません。`Win+L`、`Ctrl+Alt+Del` などの OS 予約操作は Windows が所有します。

| 操作                                 | Windows での実装                                                                                                                                                                                                                 |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ターミナル・Btop・Neovim・LazyDocker | `NixOS` WSL の Ghostty をホームディレクトリで開き、対象 CLI を起動                                                                                                                                                               |
| ブラウザ・プライベートブラウザ       | NixOS-WSL の Chrome を通常 / incognito で起動                                                                                                                                                                                    |
| ファイルマネージャー                 | `Win+Shift+F` で Nix が導入する NixOS-WSL の Nautilus（Files）を WSLg で起動                                                                                                                                                     |
| Spotify・1Password・Obsidian・Signal | Nix で導入した NixOS-WSL のアプリを WSLg で起動。Windows 版への fallback は行わない                                                                                                                                              |
| HEY Calendar / Email                 | WSL Chrome の app window で HEY の該当ページを開く                                                                                                                                                                               |
| ChatGPT・Google Messenger・WhatsApp  | WSL Chrome の app window で各 web アプリを開く                                                                                                                                                                                   |
| コピー・カット・ペースト・履歴       | 前面アプリに応じて runtime がキーを送信。Windows アプリは `Ctrl+C/X/V`、WSLg Ghostty はコピー・ペーストに `Ctrl+Shift+C/V`。Ghostty の `Win+X` は端末出力を削除できないためコピーとして扱う。履歴は Windows のクリップボード履歴 |
| スクリーンショット編集               | Snipping Tool で範囲を選び、画像を `Pictures/Screenshots` に保存して Paint で開く                                                                                                                                                |
| スクリーンショットをコピー・録画     | Snipping Tool の範囲選択・録画 (`Win+Shift+S` / `Win+Shift+R`)                                                                                                                                                                   |
| カラーピッカー                       | PowerToys Color Picker。モジュールを有効化し `Win+PrintScreen` を設定                                                                                                                                                            |
| 現在の URL 保存                      | 通常の WSL Chrome の URL を Windows の `Documents/Bookmarks/saved-urls.jsonl` に追記。元のクリップボードを復元。アドレスバーのない app window では明示エラー                                                                     |
| 通知                                 | Windows 11 通知センターの直近削除・全削除・応答不可切り替え・履歴表示                                                                                                                                                            |
| テーマ・背景                         | Windows の light/dark 切り替え。`Pictures/Wallpapers` の画像を巡回し、ディレクトリがなければ Windows 標準壁紙を使用                                                                                                              |
| 透明度・アイドル                     | 前面ウィンドウの不透明度を切り替え。アイドルキーはスリープ抑止 helper の開始・終了                                                                                                                                               |
| ナイトモード・バー・音声             | Windows 11 の夜間モード、タスクバーの自動非表示、出力デバイス巡回                                                                                                                                                                |

通知、夜間モード、音声出力は Windows 11 の英語・日本語 UI Automation label に依存します。Windows の UI 更新、表示する通知や出力デバイスの状態によって操作できない場合は、エラーを表示し `%LOCALAPPDATA%/dotfiles/keybindings/actions.log` に記録します。録画は録画 shortcut に対応した Snipping Tool が必要です。管理者権限のアプリにはキー送信や透明度変更が制限される場合があります。確認できた実キーと未確認・修正中の操作は [反映・確認記録](./keybindings-verification.md) に分けて記載します。設定生成の成功だけでは全 UI 操作の成功を意味しません。

クリップボード操作で WSLg の前面アプリを判別できない場合は、`Ctrl+C` を端末へ誤送信しないようエラーにします。

クリップボード履歴が無効な環境では、初回の `Win+Ctrl+V` で表示される **[有効にする]** を選びます。これは Windows の初回操作で、キーの配布とは別です。[Microsoft の手順](https://support.microsoft.com/ja-jp/windows/apps/using-the-clipboard) を参照してください。

ブラウザ、Nautilus（Files）と Spotify / Signal / Obsidian / 1Password GUI の起動先は WSLg に統一します。これらの Linux GUI は Nix が導入します。Chrome / Spotify / Signal / Obsidian は Windows manifest から外し、既存の Windows 版は自動 uninstall しません。Windows 版 1Password は従来の `op.exe` / Git signer 連携のため維持し、GUI の起動先変更で認証方式は変えません。Windows の既定ブラウザ設定も変更しません。

PowerToys の他の割り当てと設定を維持しながら Keyboard Manager / Color Picker を有効化し、必要な場合は PowerToys を再起動します。以後は管理対象の割り当てを更新し、keyboard engine に再読み込みを通知します。GlazeWM / Zebar / AutoHotkey は導入・起動しません。以前配置した Startup shortcut と実行中プロセスは自動削除・停止しません。

修飾キーなしの `PrintScreen` も Keyboard Manager の実行 engine に配置します。現行の PowerToys editor では、この割り当てを GUI でオフ・オンすると保持されない場合があるため、変更は Nix の正本から export / chezmoi で反映してください。

Windows の追加ブラウザーは Dia を管理します。WinGet / Microsoft Store の登録がないため、Windows 11 x64 向けの公式 MSIX と依存パッケージを `windows/winget/packages.json` の `direct` source に URL・SHA256・package identity とともに固定し、既存 installer から導入・検証します。macOS は Nix 管理の Dia、WSL のブラウザーキーは Chrome を使用します。

## Export と反映手順

```powershell
task keybindings:export
task chezmoi
```

キーを変更した開発環境で `task keybindings:export` を実行し、正本の Nix ファイルと生成した JSON を一緒にコミットします。Windows での export は WSL の Nix を使います。chezmoi はコミット済み JSON と Windows action script を配置し、Ghostty / Neovim の export を NixOS-WSL の `~/.config/dotfiles/keybindings/` にコピーします。chezmoi 実行時に Nix の評価・ビルドは行いません。GitHub Actions は export と Nix 定義の一致を検査し、自動生成・自動コミットは必要ありません。

通常の `install.cmd` は Windows GUI アプリの導入、NixOS-WSL の準備・同期、`nrs`、Windows chezmoi の順に実行します。`nrs` は `dotfiles.keybindings.fromWindowsExport` を有効にした WSL のアプリ loader を配置し、その後に chezmoi が export を配置します。既存環境でも loader 導入時は一度 `nrs` が必要です。以後のキー変更は export と `task chezmoi` で反映し、Neovim の再起動と Ghostty の設定再読み込みで読み込みます。native Unix のアプリは同じ Nix 定義を直接読みます。

## ターミナルとの境界と検証

デスクトップ配列は各 OS の desktop adapter が扱います。Ghostty と WezTerm は split・tab・pane 移動に共通の直接キーを使い、WezTerm の固有操作と Herdr の操作には [キーバインド統一方針](./keybindings.md) の `Ctrl+Space` を使います。WSL のターミナル操作は Windows のデスクトップ操作から独立した層です。Ghostty / WezTerm のサイズ変更量は10 / 100ピクセルであり、行数ではありません。

WSLg は Win キーを含む resize の組み合わせを Ghostty へ届けないため、`ghostty-windows.nix` が8件の transport remap と WSL 向け Ghostty 設定を生成します。正本の Win キー配列は変えず、PowerToys が `msrdc.exe` に対して内部用の Win を含まないキーへ変換します。この適用範囲は Ghostty だけでなく WSLg 全体です。同じ resize キーは他の WSLg アプリでも変換されます。Windows native アプリには適用しません。

Nix の検証では共通キーの重複、renderer の出力、host import の境界を確認します。実機では対象セッションで端末起動、方向移動、workspace 切り替えと移動、floating、全画面をキー入力で確認します。Nix 評価や設定生成の成功だけでは compositor の起動、macOS の Accessibilityは確認できません。

`nix build .#checks.aarch64-darwin.aerospace-workspace-cycle` は生成した巡回スクリプトを実行し、1〜10 の順序、scratchpad の除外、CLI エラーの伝播を検証します。これは CLI 境界の検証であり、macOS の実キー入力テストを置き換えません。
