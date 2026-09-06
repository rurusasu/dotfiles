# NixOS-WSL インストールと初期 setup

このドキュメントは、リポジトリルートの `install.cmd` から現在の NixOS-WSL と dotfiles を導入する手順です。
NixOS-WSL 公式の `.wsl` パッケージを使用し、初回起動後にこのリポジトリの Flake と NixOS/
Home Manager 設定を適用します。

## 前提

- Windows 10 version 2004 (build 19041) 以降、または Windows 11
- WSL 2
- 管理者権限の PowerShell（WSL 基盤を初めて有効化するとき）
- Git
- PowerShell 7 (`pwsh`) 推奨

NixOS-WSL は Windows Store 版 WSL 2 を推奨します。`wsl --install --from-file` を使うには
WSL 2.4.4 以降が必要です。古い WSL では installer が `wsl --import --version 2` に
フォールバックします。

公式資料:

- [NixOS-WSL Installation](https://nix-community.github.io/NixOS-WSL/install.html)
- [Microsoft: Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

## インストール手順

### 1. WSL 基盤を準備する

管理者として PowerShell を起動し、WSL が未導入の場合だけ実行します。

```powershell
wsl --install --no-distribution
```

再起動を求められた場合は Windows を再起動し、PowerShell を開き直します。既存の WSL が
動作している場合はこの手順を省略できます。WSL を更新する場合は次を実行します。

```powershell
wsl --update
wsl --status
```

### 2. dotfiles を取得して installer を実行する

`install.cmd` はリポジトリルートから実行します。`windows` ディレクトリへ移動する必要はありません。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
.\install.cmd
```

初回に WSL がまだ準備できていない場合、installer は WSL 基盤の有効化後に再起動を要求します。
再起動後、同じ `install.cmd` を再実行してください。

引数なしでは core 環境だけを適用します。追加サービスは必要な場合だけ選択します。

```powershell
.\install.cmd -WithOllama
.\install.cmd -WithDocker
.\install.cmd -WithMLflow
.\install.cmd -WithHindsight
.\install.cmd -WithHermes
```

### 3. NixOS を起動する

```powershell
wsl -d NixOS
```

## installer の実際の処理

現在の Windows の処理経路は次のとおりです。

```text
install.cmd
  -> scripts/powershell/install.ps1
  -> NixOS-WSL の latest release asset を GitHub API から取得
  -> nixos.wsl が使える場合は wsl --install --from-file
     （WSL 2.4.4 未満または失敗時は wsl --import --version 2）
  -> scripts/sh/nixos-wsl-postinstall.sh
  -> nix flake update
  -> nixos-rebuild switch --flake ...#nixos --impure
```

release asset は通常 `nixos.wsl` を優先し、古い release 形式では
`nixos-wsl.tar.gz` または `nixos-wsl-legacy.tar.gz` を使用します。既に同名の WSL
ディストリビューションが登録されている場合は再インストールせず、既存の状態を使います。

postinstall は `--user` がなければ UID 1000 の通常ユーザーを検出します。検出したユーザーの
名前、home、UID、GID、primary group を NixOS、Home Manager、`wsl.defaultUser` に渡すため、
通常の再構成でユーザーが `nixos` に戻ることはありません。

## リポジトリ同期方式

既定値は `link` です。Windows 側の checkout を WSL から参照し、`~/.dotfiles` をその checkout
へリンクします。

```text
Windows checkout
    |
    | sync-mode=link (既定)
    v
WSL ~/.dotfiles -> /mnt/<drive>/<path>/dotfiles
    |
    | nixos-rebuild switch --flake ...#nixos
    v
NixOS system + Home Manager
```

PowerShell から方式を指定できます。

```powershell
# link: Windows 側 checkout を直接参照（既定）
.\install.cmd -SyncMode link -SyncBack lock

# repo: リポジトリ全体を WSL の ~/.dotfiles にコピー
.\install.cmd -SyncMode repo -SyncBack lock

# nix: nix ディレクトリだけを WSL 側へコピー
.\install.cmd -SyncMode nix -SyncBack lock

# none: 既存の WSL 側 ~/.dotfiles をそのまま使用
.\install.cmd -SyncMode none -SyncBack none
```

`-SyncBack repo` は `repo` または `nix` 方式で WSL 側の変更を Windows 側 checkout に戻す場合に
明示します。通常の初回 setup では `lock` を使い、生成・更新された `flake.lock` だけを戻します。

## 主な installer 引数

```powershell
# ディストリビューション名と VHD の保存先
.\install.cmd -DistroName NixOS -InstallDir "$env:USERPROFILE\NixOS"

# 特定の NixOS-WSL release を使う場合（例: 2605.7.2）
.\install.cmd -ReleaseTag 2605.7.2

# 対話的な終了待ちを抑止
.\install.cmd -NoPause
```

通常は `-ReleaseTag` を指定せず、NixOS-WSL の latest release を使用します。`InstallDir` は
新規インストール時に空のディレクトリである必要があります。

## 手動 postinstall

installer 全体ではなく、既存の NixOS-WSL に dotfiles の postinstall だけを適用する場合は、
WSL 形式のパスで実行します。

```bash
sudo bash /mnt/d/path/to/dotfiles/scripts/sh/nixos-wsl-postinstall.sh \
  --user <USER> \
  --sync-mode link \
  --sync-source /mnt/d/path/to/dotfiles \
  --sync-back lock
```

`/mnt/d/path/to/dotfiles` は実際の checkout の WSL パスに置き換えてください。postinstall が
使用する主な設定は次のとおりです。

- `nix/hosts/wsl/default.nix`: NixOS-WSL host の entrypoint
- `nix/hosts/wsl/configuration.nix`: WSL 固有の system 設定
- `nix/home/wsl.nix`: WSL 固有の Home Manager 設定
- `/etc/nixos/hardware-configuration.nix`: native NixOS 用。NixOS-WSL では通常不要

## system version と `system.stateVersion`

NixOS のパッケージや system の更新は `flake.lock` の `nixpkgs` input で決まります。この
リポジトリは `nixos-unstable` を使用し、初回 postinstall と通常の更新経路で `nix flake update`
を実行します。WSL 内の更新は次のいずれかを使います。

```bash
# dotfiles installer の更新経路
nrs

# 状態を確認してから明示的に rebuild
nix flake update --flake ~/.dotfiles
nixos-rebuild switch --flake ~/.dotfiles#nixos --impure
```

一方、`nix/hosts/wsl/configuration.nix` の次の値は、パッケージの最新版を選択する値ではありません。
このリポジトリでは WSL の初期構成・移行先を現行 stable の NixOS 26.05 に合わせています。

```nix
system.stateVersion = "26.05";
```

これは既存の stateful data と互換性を保つための基準です。既存の WSL 環境へこの変更を適用する場合は、
Docker、データベース、各種 `/var/lib` のデータをバックアップし、変更後の generation と runtime を
確認してください。パッケージや system の実体は引き続き `flake.lock` の `nixpkgs` input で決まります。
このリポジトリの flake は `nixos-unstable` を使用するため、stable の `system.stateVersion` と
unstable の実体 version が異なることがあります。

- [NixOS Wiki: When do I update stateVersion?](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion)
- [NixOS 26.05 release](https://nixos.org/blog/announcements/2026/nixos-2605/)

## 動作確認

Windows 側:

```powershell
wsl --list --verbose
wsl -d NixOS
```

WSL 側:

```bash
readlink -f /run/current-system
nixos-rebuild list-generations
readlink -f ~/.dotfiles
```

`nrs` を実行した後、必要な CLI と chezmoi の適用状態を確認します。Windows 側の runtime を
確認する場合は、リポジトリルートで次を実行します。

```powershell
.\scripts\powershell\Test-Environment.ps1 -Runtime
```

installer の途中で停止した場合は、完了済みの宣言状態を再利用できるため、同じ `install.cmd` を
再実行してください。既存のディストリビューションや install directory を変更する場合は、
対象の VHD とデータを確認してから操作してください。

## パッケージ追加方法

パッケージ追加は [Nix package management](./package-management.md) を参照してください。
