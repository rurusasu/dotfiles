# NixOS-WSL インストールと初期 setup

公式の `nixos.wsl` を手動導入し、独立した
`scripts/powershell/lib/Invoke-NixosWslSetup.ps1` で checkout を同期して NixOS/Home Manager を適用します。
Windows の `install.cmd` は GUI アプリ専用です。CLI、管理者フェーズ、chezmoi、WSL の setup は実行せず、
WSL 用引数も受け取りません。

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

処理経路は Windows GUI installer と独立しています。

```text
公式 nixos.wsl を手動導入
  -> Invoke-NixosWslSetup -Context $context
  -> checkout 同期と /etc/nixos/dotfiles.json 保存
  -> nix flake update
  -> nixos-rebuild switch --flake path:<checkout>#nixos --impure
```

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
通常の反映では保存値を維持します。`install.cmd` は NixOS の設定を変更しません。

明示的に移行する場合は VHD、Docker、データベース、各種 `/var/lib` のデータをバックアップし、
使用中のモジュールの移行可否を確認してください。反映後は generation、
`/run/current-system`、Docker とデータベースなどの状態を確認します。

```bash
nixos-rebuild list-generations
readlink -f /run/current-system
```

- [NixOS Wiki: When do I update stateVersion?](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion)
