# NixOS-WSL インストールと初期 setup

Windows の `install.cmd` は GUI アプリ導入後に NixOS-WSL をセットアップします。
既存 distro は再利用し、未登録なら公式の `nixos.wsl` を取得して登録します。
`scripts/powershell/lib/Invoke-NixosWslSetup.ps1` が checkout を同期して NixOS/Home Manager を適用します。

## 推奨: Windows installer から実行する

checkout のルートで通常ユーザーの PowerShell から実行します。

```powershell
.\install.cmd
# GUI アプリだけを導入・更新
.\install.cmd -UserPhaseOnly
# 既存 WSL checkout を使用し、逆同期を行わない
.\install.cmd -DistroName NixOS -SyncMode none -SyncBack none
```

実行順序は `taskfiles/install/taskfile.yml` の `install:windows` が管理します。
Task がなければ installer 専用 cache に取得します。WSL 基盤の有効化だけ UAC 昇格し、
成功後は再起動して `install.cmd` を再実行するよう案内します。distro の登録と設定適用は元のユーザーで行います。
再起動待ちはエラー表示せず終了コード `3010` を返し、`Setup Complete!` は表示しません。
初回導入で設定適用を二重実行しません。失敗時は非ゼロ終了し、`Setup Complete!` は表示しません。

`-DistroName`、`-InstallDir`、`-ReleaseTag`、`-SyncMode`、`-SyncBack`、`-StateVersion`、
`-ForcePostInstall` を指定できます。`StateVersion` は省略時に既存の値を保持します。
同期オプションと既存環境のバックアップについては後述を参照してください。
以下は distro の手動導入と、設定適用だけを独立して実行する場合の手順です。

## 前提

- Windows 10 version 2004 (build 19041) 以降、または Windows 11
- WSL 2（以下の `--from-file` 手順には WSL 2.4.4 以降）
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

. ./scripts/powershell/lib/WindowsEnvironment.ps1
. ./scripts/powershell/lib/SetupHandler.ps1
. ./scripts/powershell/lib/Invoke-ExternalCommand.ps1
. ./scripts/powershell/lib/Invoke-NixosWslSetup.ps1
$context = [SetupContext]::new((Get-Location).Path)
$context.DistroName = 'NixOS'
$context.Options['SyncMode'] = 'link'
$context.Options['SyncBack'] = 'lock'
Invoke-NixosWslSetup -Context $context
```

`SetupContext` は PowerShell class のため、新しいセッションで一度だけ読み込んでください。
既存の stateVersion は省略時に保持します。新規構成で 26.05 を明示する場合だけ、
実行前に `$context.Options['StateVersion'] = '26.05'` を設定します。

設定適用だけを独立して呼び出すこともできます。

```text
公式 nixos.wsl を手動導入
  -> Invoke-NixosWslSetup -Context $context
  -> checkout 同期と /etc/nixos/dotfiles.json 保存
  -> nix flake update --flake path:<checkout>
  -> nixos-rebuild switch --flake path:<checkout>#nixos --impure
```

初期 NixOS-WSL イメージには Git CLI がないため、ローカル checkout は明示的な `path:` flake として扱います。
通常のファイルシステムパスを渡すと Git flake として自動判定され、Git CLI が必要になるためです。

保存済みの選択ユーザーを再利用し、なければ UID 1000 の通常ユーザーを検出します。
名前・home・UID・GID・primary group・正確な checkout パスを
`/etc/nixos/dotfiles.json` に保存し、Nix の identity module が読み取ります。

## 同期オプション

`$context.Options` で指定します。

| Option                      | 値と意味                                                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `SyncMode`                  | `link`（既定）: Windows checkout への symlink、`repo`: 完全コピー、`nix`: 既存 checkout の nix/ だけ同期、`none`: 既存 WSL checkout を使用 |
| `SyncBack`                  | `lock`（既定）: flake.lock だけ戻す、`none`: 戻さない、`repo`: checkout を戻す                                                             |
| `StateVersion`              | 明示する場合は `YY.MM`。省略時は既存の明示値を維持                                                                                         |
| `ForcePostInstall`          | 既存 checkout が競合した場合、隣接する `.backup-<ID>` へ移動して同期を許可                                                                 |
| `PostInstallTimeoutSeconds` | 各 WSL setup コマンドのタイムアウト（既定 1800 秒）                                                                                        |

`link` は Windows 側の変更が即時に見えます。既に同じ場所へのリンクなら維持します。
`repo` / `nix` と逆同期はファイルを上書きし得るため、両側の checkout をバックアップしてください。
`nix` は既に flake.nix・flake.lock・scripts/ を持つ完全な WSL checkout が必要で、
`SyncBack = 'repo'` と併用できません。
`ForcePostInstall` は通常設定せず、競合する checkout を退避する必要がある場合だけ明示します。
Flake inputs の更新失敗時は構成を反映しません。

検証済みの `flake.lock` をそのまま適用する場合は、setup 前に
`$context.Options['UpdateFlakeInputs'] = $false` を指定します。既定値は `$true` です。
WSL 内の再適用では `task nrs UPDATE_FLAKE_INPUTS=false` を使います。
どちらも更新を省略し、`--no-update-lock-file` で lock の変更を禁止します。
WSL CI は初回 setup と `nrs` の両方にこの指定を使い、PR の head SHA に含まれる
lock と事前ビルドの依存を一致させます。

## 通常の反映

setup 済みの WSL では次を実行します。

```bash
~/.dotfiles/install.sh
```

WSL 固有構成は `nix/hosts/x86_64-linux/wsl/`、
ユーザー・stateVersion は `/etc/nixos/dotfiles.json` を
`nix/hosts/shared/nixos/identity.nix` が読み取ります。
native NixOS 用の `/etc/nixos/hardware-configuration.nix` は WSL では通常不要です。

## system version と system.stateVersion

`system.stateVersion` はパッケージの更新版ではなく、永続データの互換性を決める schema です。
既存の 25.05 WSL 環境を単なるパッケージ更新で 26.05 に変更しないでください。
通常の反映では保存値を維持します。`install.cmd` も `-StateVersion` を省略すれば既存の値を維持します。

明示的に移行する場合は VHD、Docker、データベース、各種 `/var/lib` のデータをバックアップし、
使用中のモジュールの移行可否を確認してください。反映後は generation、
`/run/current-system`、Docker とデータベースなどの状態を確認します。

```bash
nixos-rebuild list-generations
readlink -f /run/current-system
```

- [NixOS Wiki: When do I update stateVersion?](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion)
