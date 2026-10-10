# NixOS-WSL インストールと初期 setup

このドキュメントは、公式の `nixos.wsl` を手動で導入し、初回起動後に
`scripts/sh/nixos-wsl-postinstall.sh` でこのリポジトリの Flake と NixOS/Home Manager 設定を適用する手順です。
Windows の `install.cmd` は GUI アプリ専用です。CLI、管理者フェーズ、chezmoi、WSL の setup は実行せず、
このドキュメントの WSL 用引数も受け取りません。

## 前提

- Windows 10 version 2004 (build 19041) 以降、または Windows 11
- WSL 2（以下の `--from-file` 手順には WSL 2.4.4 以降）
- 管理者権限の PowerShell（WSL 基盤を初めて有効化するとき）
- Git

NixOS-WSL は Windows Store 版 WSL 2 を推奨します。`wsl --install --from-file` を使うには
WSL 2.4.4 以降が必要です。古い WSL は先に更新してください。自動フォールバックはありません。
更新できない環境の手動 `wsl --import` 手順は公式資料を参照してください。

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
wsl --version
wsl --status
```

### 2. 公式の NixOS-WSL を導入する

[公式 release](https://github.com/nix-community/NixOS-WSL/releases/latest) から `nixos.wsl` を
ダウンロードし、PowerShell で実行します。パスは実際の保存先に置き換えてください。

```powershell
wsl --install --from-file "$env:USERPROFILE\Downloads\nixos.wsl"
```

既定の登録名は `NixOS` です。登録名やディスク保存先を変更する場合は、公式手順と
`wsl --help` の `--name` / `--location` を参照してください。既存の `NixOS` がある場合は
再インストールせず、次の手順でその環境を使用します。既存ディストリビューションの削除は不要です。

### 3. dotfiles を取得して NixOS を起動する

Windows 側に checkout がなければ取得します。既存の checkout があれば再利用してください。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
wsl -d NixOS
```

### 4. WSL 内で postinstall を実行する

公式手順に従い、初回は通常ユーザーのパスワード設定と channel の更新を行います。

```bash
passwd
sudo nix-channel --update
```

その後、NixOS 内で次を実行します。`/mnt/d/path/to/dotfiles` は Windows checkout の実際の WSL パスに置き換えてください。

```bash
sudo bash /mnt/d/path/to/dotfiles/scripts/sh/nixos-wsl-postinstall.sh \
  --flake-name nixos \
  --sync-mode link \
  --sync-source /mnt/d/path/to/dotfiles \
  --sync-back lock
```

既存環境では `--state-version` を省略して保存済みの stateVersion を維持します。
新規環境でリポジトリの新規構成用 schema を明示的に採用する場合は `--state-version 26.05` を追加します。
適用前に後述の [stateVersion の注意点](#system-version-と-systemstateversion)を確認してください。

## postinstall の実際の処理

Windows の GUI installer とは独立した処理経路です。

```text
公式 nixos.wsl を手動ダウンロード
  -> PowerShell: wsl --install --from-file <path>
  -> PowerShell: wsl -d NixOS
  -> WSL: sudo bash scripts/sh/nixos-wsl-postinstall.sh [options]
  -> nix flake update
  -> user-aware nixos-rebuild-with-user.sh switch --flake ...#nixos --impure
```

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

WSL 内の Bash で postinstall に方式を指定します。`--sync-source` を省略すると、実行した
スクリプトが属するリポジトリルートが同期元になります。

```bash
postinstall=/mnt/d/path/to/dotfiles/scripts/sh/nixos-wsl-postinstall.sh

# link: Windows 側 checkout を直接参照（既定）
sudo bash "$postinstall" --flake-name nixos --sync-mode link --sync-back lock

# repo: リポジトリ全体を WSL の ~/.dotfiles にコピー
sudo bash "$postinstall" --flake-name nixos --sync-mode repo --sync-back lock

# nix: 既存の完全な WSL 側 checkout に nix ディレクトリだけを同期
#      （fresh install では link または repo を使用）
sudo bash "$postinstall" --flake-name nixos --sync-mode nix --sync-back none

# none: 既存の WSL 側 ~/.dotfiles をそのまま使用
sudo bash "$postinstall" --flake-name nixos --sync-mode none --sync-back none
```

`nix` 方式は既存の完全な WSL 側 checkout に対する差分同期です。`flake.nix`、`flake.lock`、
`scripts/` などが既に存在する必要があり、fresh install では使用しないでください。
また、部分同期した `nix` 方式では `--sync-back repo` を使わないでください。Windows 側 checkout
全体を上書きする対象ではありません。`--sync-back repo` は完全な `repo` 方式で WSL 側の変更を
Windows 側 checkout に戻す場合だけ使用します。通常の初回 setup では `lock` を使い、生成・更新
された `flake.lock` だけを戻します。`repo` 方式で `--sync-back` を省略すると既定値は `repo` になるため、
上の例では安全のため明示的に `lock` を指定しています。`repo` の同期・逆同期はファイルを上書きし、
rsync がある場合は同期先だけにあるファイルを削除し得ます。事前に両方の checkout をバックアップしてください。

## 主な postinstall 引数

- `--user <name>`: 既存の通常ユーザーを指定（省略時は自動検出）
- `--repo-dir <path>`: WSL 側の配置先（既定 `/home/<user>/.dotfiles`）
- `--flake-name <name>`: Flake attribute（このリポジトリでは `nixos`）
- `--sync-mode link|repo|nix|none`: 同期方式
- `--sync-source <path>`: 同期元の WSL パス
- `--sync-back lock|none|repo`: 逆同期方式（`repo` は完全同期時だけ使用）
- `--state-version <YY.MM>`: 新規構成または承認済み移行の stateVersion を明示
- `--skip-flake-update`: Flake inputs の更新を省略
- `--force`: 既存の配置先を使うことを明示的に許可
- `--help`: ヘルプ表示

```bash
sudo bash /mnt/d/path/to/dotfiles/scripts/sh/nixos-wsl-postinstall.sh --help
```

`--force` は通常指定しないでください。`link` 方式では既存の実ディレクトリやファイルを削除して
シンボリックリンクに置き換えます。`repo` 方式でも既存の内容を上書き・削除し得ます。
必要な場合は、先に checkout と VHD/stateful data のバックアップを作成してください。
postinstall は release のダウンロードや WSL ディストリビューションの登録は行いません。
使用する主な設定は次のとおりです。

- `nix/hosts/x86_64-linux/wsl/default.nix`: NixOS-WSL host の entrypoint
- `nix/hosts/x86_64-linux/wsl/configuration.nix`: WSL 固有の system 設定
- `nix/hosts/x86_64-linux/wsl/home.nix`: WSL 固有の Home Manager 設定
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
~/.dotfiles/scripts/sh/nixos-rebuild-with-user.sh switch --flake ~/.dotfiles#nixos --impure
```

一方、`nix/hosts/x86_64-linux/wsl/configuration.nix` の `system.stateVersion` は、パッケージの最新版を選択する値では
ありません。このリポジトリの新規構成用の値は 26.05 です。既存環境では
`/var/lib/dotfiles/system-state-version` の保存値を維持し、保存値がない既存環境は 25.05 を既定にします。

```nix
system.stateVersion = stateVersion;
```

新規構成で 26.05 を採用するときは、postinstall に `--state-version 26.05` を明示します。
`--state-version` を省略した postinstall と通常の `nrs` は既存の保存値を保持します。
`install.cmd` は NixOS の設定を変更しません。既存の 25.05 WSL 環境から 26.05 へ
移行する場合は、単なるパッケージ更新ではなく state schema の移行として扱ってください。適用前に VHD、
Docker、データベース、各種 `/var/lib` のデータをバックアップし、使用中のモジュールの移行可否を確認して
ください。適用後は generation、`/run/current-system`、Docker、データベース、各種 stateful data の
runtime を検証します。
パッケージや system の実体は引き続き `flake.lock` の `nixpkgs` input で決まります。
このリポジトリの flake は `nixos-unstable` を使用するため、stable の `system.stateVersion` と
unstable の実体 version が異なることがあります。

既存の 25.05 環境から明示的に移行する場合は、次の順で承認します。`dry-build` が成功しても runtime
data の互換性を保証するものではないため、バックアップと rollback generation を確認してから `switch`
してください。

```bash
nix flake update --flake ~/.dotfiles
DOTFILES_STATE_VERSION=26.05 ~/.dotfiles/scripts/sh/nixos-rebuild-with-user.sh dry-build --flake ~/.dotfiles#nixos --impure
DOTFILES_STATE_VERSION=26.05 ~/.dotfiles/scripts/sh/nixos-rebuild-with-user.sh switch --flake ~/.dotfiles#nixos --impure
nixos-rebuild list-generations
readlink -f /run/current-system
```

新規インストール時に値を指定する場合も、WSL 内の postinstall の `--state-version` を使用します。

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

NixOS/Home Manager の適用結果と必要な Unix CLI を確認します。Unix の設定配布は Home Manager が担当し、
chezmoi は使用しません。Windows の GUI アプリ導入とは別の検証です。

postinstall の途中で停止した場合は、エラーを解消して同じ Bash コマンドを再実行してください。
WSL のインストールコマンドや `install.cmd` を再実行する手順ではありません。
既存のディストリビューションやディスク保存先を変更する場合は、
対象の VHD とデータを確認してから操作してください。

## パッケージ追加方法

パッケージ追加は [Nix package management](./package-management.md) を参照してください。
