# NixOS-WSL インストールと初期 setup

Windows の通常入口は `task install` です。GUI アプリ導入、NixOS-WSL の更新・反映、
Windows chezmoi の適用を順に実行します。Nix の更新と反映は WSL phase で一度だけ行います。
既存 distro は再利用し、未登録なら公式の `nixos.wsl` を取得して登録します。
登録には `wsl --install --from-file` を試し、失敗した場合は `wsl --import` に切り替えます。
`scripts/powershell/lib/Invoke-NixosWslSetup.ps1` が checkout を同期して NixOS/Home Manager を適用します。

## 推奨: Windows installer から実行する

checkout のルートで通常ユーザーの PowerShell から実行します。

```powershell
task install
```

`install.cmd` は先に PowerShell で WinGet master を適用し、Task もそこから導入します。Task の事前導入は不要です。同期オプションを指定する場合も同じ入口を使います。

```powershell
.\install.cmd
# GUI アプリだけを導入・更新
.\install.cmd -Phase Winget
# 既存 WSL checkout を使用し、逆同期を行わない
.\install.cmd -DistroName NixOS -SyncMode none -SyncBack none
```

実行順序は `taskfiles/install/taskfile.yml` の `install` が管理します。
`install.cmd` / `install.ps1` は WinGet master 適用後に `task install INSTALL_STAGE=apply` を一度呼びます。Taskfile は WSL と chezmoi の後続処理だけを実行するため、WinGet は再実行しません。master 適用に失敗した場合、または適用後も Task が見つからない場合は停止します。
WSL 基盤の有効化だけ UAC 昇格し、
成功後は再起動して `install.cmd` を再実行するよう案内します。distro の登録と設定適用は元のユーザーで行います。
再起動待ちは WSL phase が終了コード `3010` で停止し、chezmoi へ進まず、`Setup Complete!` も表示しません。状態ファイルは作りません。
直接の `task install` は Task 標準の終了コード `201`、`task --exit-code install` は `194`（Task が `3010` を8ビットへ変換した値）を返します。
起動補助の `install.cmd` / `install.ps1` は、この値を Windows 標準の `3010` に戻して返します。再起動後は同じインストールコマンドを再実行します。
初回導入で設定適用を二重実行しません。失敗時は非ゼロ終了し、`Setup Complete!` は表示しません。

`-DistroName`、`-InstallDir`、`-ReleaseTag`、`-SyncMode`、`-SyncBack`、
`-ForcePostInstall` を指定できます。`system.stateVersion` は
`nix/defaults.nix:systemDefaults` 内の `defaults.stateVersion` を使います。
同期オプションと既存環境のバックアップについては後述を参照してください。
以下は distro の手動導入と、設定適用だけを独立して実行する場合の手順です。

## 前提

- Windows 10 version 2004 (build 19041) 以降、または Windows 11
- WSL 2（手動の `--from-file` 手順に対応しているかは `wsl --help` で確認）
- 管理者権限の PowerShell（WSL 基盤を初めて有効化するときだけ）
- Git

公式資料: [NixOS-WSL Installation](https://nix-community.github.io/NixOS-WSL/install.html)、
[Microsoft: Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install)。

## 1. WSL 基盤と公式ディストリビューションを準備する

管理者 PowerShell で、WSL 未導入の場合だけ実行します。

```powershell
wsl --install --no-distribution
```

再起動を求められた場合は再起動してください。既存の WSL が動作していれば省略できます。
`wsl --version` が成功していても、`VirtualMachinePlatform` が無効だと WSL 2 は起動できません。
installer はこの状態を検出して、WSL 基盤の有効化と再起動を案内します。
WSL を更新・確認する場合は次を実行します。

```powershell
wsl --update
wsl --version
wsl --status
```

[公式 release](https://github.com/nix-community/NixOS-WSL/releases/latest) から `nixos.wsl` をダウンロードし、
通常ユーザーの PowerShell で実行します。パスは実際の保存先に置き換えてください。

```powershell
wsl --install --from-file "$env:USERPROFILE\Downloads\nixos.wsl"
wsl -d NixOS
```

既定の登録名は `NixOS` です。既存の `NixOS` がある場合は再インストールせず使用してください。
登録名・保存先の変更や旧 WSL の手動 import は公式資料と `wsl --help` を参照してください。
以下の setup は release のダウンロードやディストリビューションの登録を行いません。

初回は NixOS-WSL の案内に従って通常ユーザーのパスワードを設定します。

```bash
passwd
exit
```

## 2. Windows checkout から WSL setup を明示的に実行する

Windows 側に checkout がなければ clone し、通常ユーザーの新しい PowerShell をそのルートで開きます。
既存 checkout は再利用してください。次の呼び出しは WSL 内の構成を変更するため、
既存環境では先に VHD と stateful data をバックアップしてください。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles

. ./scripts/powershell/lib/Invoke-ExternalCommand.ps1
. ./scripts/powershell/lib/Invoke-NixosWslSetup.ps1
Invoke-NixosWslSetup -Repository (Get-Location).Path -DistroName NixOS -SyncMode link -SyncBack lock
```

NixOS の stateVersion は共通 entrypoint が設定し、追加引数の指定は不要です。

設定適用だけを独立して呼び出すこともできます。

```text
公式 nixos.wsl を手動導入
  -> Invoke-NixosWslSetup -Repository <Windows checkout> -DistroName NixOS
  -> checkout 同期（公式既定ユーザー nixos）
  -> nix flake update --flake path:<checkout>
  -> nixos-rebuild switch --flake path:<checkout>#nixos --impure
```

初期 NixOS-WSL イメージには Git CLI がないため、ローカル checkout は明示的な `path:` flake として扱います。
通常のファイルシステムパスを渡すと Git flake として自動判定され、Git CLI が必要になるためです。

[公式手順](https://nix-community.github.io/NixOS-WSL/install.html)の標準アカウントは `nixos` です。セットアップは flake の `wsl.defaultUser` を読み取り、WSL の現在の既定ユーザーと一致することを確認します。設定済みのカスタムユーザーも利用できます。`nix/defaults.nix:systemDefaults` は
`wsl.defaultUser` を使って Home Manager を接続し、アカウント名と UID の既定値は NixOS-WSL module に任せます。
ユーザー名・UID/GID・checkout を独自 JSON に保存する処理はありません。

## 同期オプション

`Invoke-NixosWslSetup` の名前付き引数で指定します。

| Option             | 値と意味                                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `SyncMode`         | `link`（既定）: Windows checkout への symlink、`repo`: 完全コピー、`nix`: 既存 checkout の nix/ だけ同期、`none`: 既存 WSL checkout を使用 |
| `SyncBack`         | `lock`（既定）: flake.lock だけ戻す、`none`: 戻さない、`repo`: checkout を戻す                                                             |
| `ForcePostInstall` | 既存 checkout が競合した場合、隣接する `.backup-<ID>` へ移動して同期を許可                                                                 |
| `TimeoutSeconds`   | 各 WSL setup コマンドのタイムアウト（既定 1800 秒）                                                                                        |

`link` は Windows 側の変更が即時に見えます。既に同じ場所へのリンクなら維持します。
`repo` / `nix` と逆同期はファイルを上書きし得るため、両側の checkout をバックアップしてください。
`nix` は既に flake.nix・flake.lock・scripts/ を持つ完全な WSL checkout が必要で、
`SyncBack = 'repo'` と併用できません。
`ForcePostInstall` は通常設定せず、競合する checkout を退避する必要がある場合だけ明示します。
Flake inputs の更新失敗時は構成を反映しません。

検証済みの `flake.lock` をそのまま適用する場合は、`Invoke-NixosWslSetup` に
`-UpdateFlakeInputs $false` を渡します。既定値は `$true` です。
WSL 内の再適用では `task nrs UPDATE_FLAKE_INPUTS=false` を使います。
どちらも更新を省略し、`--no-update-lock-file` で lock の変更を禁止します。
WSL CI は setup を更新なしで一度だけ実行し、PR の head SHA に含まれる
lock と事前ビルドの依存を一致させます。

## 通常の反映

setup 済みの WSL では次を実行します。

```bash
~/.dotfiles/install.sh
```

WSL の system / ユーザー設定と module 選択は `nix/defaults.nix:systemDefaults`、アプリ設定は `nix/modules/` に置きます。
WSL のユーザーは `wsl.defaultUser`、ホームは `users.users.<name>.home` から取得し、
ユーザー名と stateVersion の既定値は `nix/defaults.nix:systemDefaults` 内の `defaults` で管理します。
architecture は構成の `system` 引数で指定し、CPU 別ディレクトリは設けません。
native NixOS 用の `/etc/nixos/hardware-configuration.nix` は WSL では通常不要です。

## WSLg のフォント

管理するアプリの既定フォントは `UDEV Gothic NF` に統一します。フォントの選択・導入は Nix、Windows の配置・登録は chezmoi が担当します。不足グリフ用には color emoji を残します。Windows 自体のシステム UI フォントや、Web サイトが CSS で指定したフォントは強制変更しません。

`nix/defaults.nix` の WSL 設定は WSLg server が読める通常ファイルとして UDEV の Regular / Bold と color emoji を配置します。WSLg 用 fontconfig の正本は `nix/modules/fonts/wsl-fontconfig.conf` です。server 標準の `/etc/fonts/fonts.conf` を読み込んだ後、解決された `sans-serif` に UDEV を優先指定し、Pango の titlebar にも適用します。

chezmoi はこの XML を `%USERPROFILE%/.config/dotfiles/wslg-fontconfig.conf` に配置し、`%USERPROFILE%/.wslgconfig` の `FONTCONFIG_FILE` を Windows home の `/mnt/<drive>/...` パスへ向けます。XML の参照先を Windows 側に置くことで、特定の user distro 内の設定や起動順に依存させません。フォント方針を chezmoi 側へ重複定義しません。

GTK の画面内フォントは `nix/modules/fonts/default.nix` が GTK 3 / 4 と設定ポータルへ配布します。WSL host は `programs.dconf.enable` で永続設定に必要な service を登録します。

反映は WSL で `nrs`、Windows で `task chezmoi` の順です。WSLg の新しい環境変数と titlebar font cache は、次の WSLg 再起動時に読み込まれます。作業を保存して Linux GUI アプリを閉じた後、Windows で `wsl --shutdown` を実行し、通常どおりアプリを起動してください。2026-10-14 に再起動後の通常 Chrome titlebar と Nautilus の UDEV・日本語表示を実機確認しました。

## WSLg の GPU 描画

WSL host は `wsl.useWindowsDriver = true` で Windows の D3D12 / DXCore ライブラリを
`/run/opengl-driver/lib` に接続します。`LD_LIBRARY_PATH` にそのディレクトリを設定し、
`GALLIUM_DRIVER=d3d12` で Mesa の描画経路を選択します。
Ghostty などの OpenGL アプリが CPU 描画の `llvmpipe` にフォールバックするのを防ぎます。
`platform = "wsl"` の `systemDefaults` が Windows driver・ポータル・ユーザーの描画環境を管理します。
シェルには `home.sessionVariables`、systemd 経由の GUI 起動には `systemd.user.sessionVariables` で渡します。
詳細は [NixOS-WSL の option](https://nix-community.github.io/NixOS-WSL/options.html#wsl.useWindowsDriver) と
[WSLg の D3D12 自動選択の問題](https://github.com/microsoft/wslg/issues/1332) を参照してください。

反映後は新しい WSL シェルで確認します。既に起動している Ghostty は再起動してください。

```bash
nix shell --inputs-from ~/.dotfiles nixpkgs#mesa-demos -c glxinfo -B
```

`OpenGL renderer string` が `D3D12 (<GPU 名>)`、`Accelerated` が `yes` なら GPU 描画です。
`direct rendering: Yes` や OpenGL のバージョンだけでは、GPU 描画かどうかは判別できません。
Wayland 側は同じ package の `eglinfo -B` で確認できます。

Windows 側には GPU メーカーの対応ドライバーが必要です。NixOS 内に native Linux 用の
NVIDIA カーネルドライバーを導入する構成ではありません。

## WSLg のデスクトップポータル

WSLg にはデスクトップセッションマネージャーがないため、`nixos-activation.service` の依存で
標準の `graphical-session.target` を起動し、ポータルを利用可能にします。
GTK backend が画面に接続できるよう、`DISPLAY=:0` と `WAYLAND_DISPLAY=wayland-0` を
systemd の `environment.d` にも渡します。通常のシェルの表示環境は WSLg が設定します。

反映後は次のコマンドで、サービス名だけでなく実際の設定取得を確認できます。

```bash
systemctl --user is-active graphical-session.target
busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings Read ss org.freedesktop.appearance color-scheme
```

Ghostty 1.3.1 の起動ログには、設定で解決する警告と upstream 由来の警告があります。

| ログ                                                   | 原因と対応                                                                                                                                    |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Portal の `startup job failed`                         | セッション target と GTK backend の環境が必要です。上記の設定と D-Bus 呼び出しで確認します。                                                  |
| `gtk-xft-dpi ... (-1)`                                 | GTK が DPI 設定を得られない場合に既定倍率を使います。Portal 起動後に解消することを実機で確認しました。                                        |
| `OSC 7 ... UriMissingHost`                             | WezTerm の連携が Ghostty 内でも読み込まれ、Zsh で空の `HOSTNAME` を使っていました。WezTerm の連携は `TERM_PROGRAM=WezTerm` に限定します。     |
| Mesa の `fd -1` / device information                   | Mesa の Linux DRM 情報取得が WSL の D3D12 経路では失敗します。これだけで CPU 描画とは判断せず、上記の renderer を確認します。                 |
| `unimplemented action=.cell_size`                      | Ghostty 1.3.1 の GTK frontend が内部のセル寸法通知を実装していない警告です。設定のキー割り当てではありません。                                |
| Adwaita の `style-dark.css` などの deprecated resource | Ghostty に同梱された旧形式のテーマ resource に対する libadwaita の警告です。ユーザーのテーマ設定エラーではありません。                        |
| `水 ... discarding ic_width metric`                    | フォントの実グリフ幅が advance を超えたため、Ghostty がフォントサイズ正規化用の測定値を破棄しています。文字自体を削除する動作ではありません。 |

上記の実装は [Ghostty 1.3.1 の GTK frontend](https://github.com/ghostty-org/ghostty/blob/v1.3.1/src/apprt/gtk/class/application.zig)、
[DPI 処理](https://github.com/ghostty-org/ghostty/blob/v1.3.1/src/apprt/gtk/class/surface.zig)、
[フォント測定](https://github.com/ghostty-org/ghostty/blob/v1.3.1/src/font/face/freetype.zig)、
[Mesa 26.2.4 の loader](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.4/src/loader/loader.c)
で確認できます。WSL で `EGL_PLATFORM=surfaceless` も試しましたが Mesa の警告は残り、
`MESA_LOADER_DRIVER_OVERRIDE=d3d12` は別の EGL 警告を生んだため、いずれも常設しません。

## system version と system.stateVersion

`system.stateVersion` は永続データの形式やサービスの既定値に使う設定値です。
ユーザーは `wsl.defaultUser` で上書きでき、既定値と stateVersion は `nix/defaults.nix:systemDefaults` 内の `defaults` で管理します。
既存環境でユーザー名を変更する場合は、[公式の変更手順](https://nix-community.github.io/NixOS-WSL/how-to/change-username.html)に従います。
通常の `switch` で改名せず、`boot` で構成を作り、WSL の停止・root での起動・再停止を行って反映します。
Windows / WSL の installer はアカウント名の不一致を検出すると `switch` 前に停止し、この公式の変更手順を案内します。
Home Manager の `home.stateVersion` も同じ `defaults.stateVersion` を参照します。
稼働する NixOS のリリースは `nixos-version`、反映後の generation は次のコマンドで確認できます。

```bash
nixos-rebuild list-generations
readlink -f /run/current-system
```

- [NixOS Wiki: When do I update stateVersion?](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion)
