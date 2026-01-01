# NixOS WSL インストール手順

このドキュメントは `windows/install-nixos-wsl.ps1` を使って NixOS を WSL に導入する手順です。

## 前提

- Windows 10/11
- WSL 有効化済み
- 管理者権限の PowerShell
- `pwsh` (PowerShell 7) を推奨

## インストール手順

1. 管理者として PowerShell を起動する。
2. リポジトリの `windows` フォルダへ移動する。
3. スクリプトを実行する。

```powershell
cd D:\my_programing\dotfiles\windows
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install-nixos-wsl.ps1
```

## よく使うオプション

- 既存の WSL 基盤を使いたい (WSL の有効化をスキップ)
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install-nixos-wsl.ps1 -SkipWslBaseInstall
```

- チャンネル更新と再構成をスキップ
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install-nixos-wsl.ps1 -SkipChannelUpdate
```

- ディストリ名とインストール先を指定
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install-nixos-wsl.ps1 -DistroName NixOS -InstallDir "$env:USERPROFILE\NixOS"
```

## 実行後の動作

`-SkipChannelUpdate` を付けない場合、インストール後に以下が自動実行されます。

```sh
nix-channel --update
nixos-rebuild switch
```

## 環境構築の自動実行

`windows/install-nixos-wsl.ps1` は既定で `scripts/nixos-wsl-postinstall.sh` を実行し、
Flake 化と Home Manager ベースの最小構成を作成します。

スキップしたい場合:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install-nixos-wsl.ps1 -SkipPostInstallSetup
```

手動で実行したい場合:

```sh
sudo bash /mnt/d/my_programing/dotfiles/scripts/nixos-wsl-postinstall.sh --user <USER> --hostname <HOST>
```

生成される主なファイル:
- `~/.dotfiles/flake.nix`
- `~/.dotfiles/nix/profiles/home/common.nix`
- `~/.dotfiles/nix/home/wsl/default.nix`
- `~/.dotfiles/nix/home/users/<USER>.nix`
- `~/.dotfiles/nix/hosts/wsl/default.nix`
- `~/.dotfiles/nix/hosts/wsl/configuration.nix`
- `~/.dotfiles/nix/hosts/wsl/hardware-configuration.nix`

## 起動方法

```powershell
wsl -d NixOS
```

## 注意点

- Windows PowerShell 5.1 だと文字化けする場合があるため、`pwsh` を推奨します。
- `InstallDir` は空ディレクトリである必要があります。
- 既に同名のディストリが登録済みの場合、インポートはスキップされます。
