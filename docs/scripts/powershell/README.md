# Windows セットアップ

## 実装

`install.cmd` → `install.ps1` → WinGet master import → Taskfile の WSL → SSH 転送 → chezmoi の順です。
Taskもmasterから導入し、Nix は lock 済みの依存を一度だけ反映します。
`-Phase Winget` / `Wsl` / `WslSsh` / `Chezmoi` はその操作だけを実行します。
`task install:ssh` でも転送先の更新だけを実行できます。

セットアップの主な実装は次の3ファイルです。

- `scripts/powershell/install.ps1`: Windowsの標準コマンドとTaskの起動、WSL基盤の昇格。
- `lib/Invoke-ExternalCommand.ps1`: native終了コード、timeout、UTF-8、PATH、標準import。
- `lib/Invoke-NixosWslSetup.ps1`: 必要時のdistro登録と、同期・lock済みのNixOS/Home Manager反映。
- `lib/Sync-WslSshNetwork.ps1`: 元ユーザーでWSLのIPを調べ、差分があるWindowsのSSH転送・firewall設定だけをUAC昇格する。TCP 2222からWSLの22へ転送し、全ネットワークプロファイルでTCP 2222のLocalSubnetだけを許可する。

通常の関数と例外を使います。クラス、結果オブジェクト、独自runnerはありません。
順序はTaskfileだけが管理し、初回導入と既存distroでsetupを重複させません。
WSL基盤の昇格が必要な初回は、成功後に3010で停止してWindows再起動を案内します。
SSH転送は差分がある場合だけ別途UACで適用します。PublicネットワークをPrivateへ自動変更しません。
Taskの194は3010に戻し、distro登録は元のユーザーで実行します。

WinGetは標準JSONをimportします。導入後にプロセスPATHを再読込し、Taskへ引き継ぎます。
開始時のPATHはcmd.exeの8191文字制限に収め、ユーザーPATHは変更しません。
chezmoiは`init --apply --force --no-tty --no-pager`を一度実行します。
WSL出力はUTF-8に統一し、日本語を含むチェックアウトパスも扱います。
WSLセットアップ失敗時は最初のエラー周辺（見つからない場合は末尾20行）と終了コードを表示し、
出力全文はWindowsの一時ディレクトリの `dotfiles-wsl-<GUID>.log` に保存します。
例外末尾の `Full log:` に表示されたパスを開くと全文を確認できます。

既存VHDはファイルを指定して再登録し、非空の導入先は上書きしません。
競合するチェックアウトはForce指定時もGUID付きで退避します。
CI は既存の `NixOS` distro を置き換えません。導入先は一時領域内の `NixOS-CI-*` に限定し、
当該 run が作成した `NixOS` だけを削除します。

## 静的検査

```bash
nix develop .#ci --command powershell-lint
```

`Invoke-StaticAnalysis.ps1` が runtime ソースの PSScriptAnalyzer と、全 PowerShell ソースの
ANSI/BOM 整合性を検査します。formatter と同じ locked nixpkgs の PowerShell / PSScriptAnalyzer を使い、
Pester や Gallery からの module 取得は不要です。CI は Build / Plan より先にこの検査を実行します。

## テスト

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1
```

- `Install.Tests.ps1`: 実launcherとTaskfile、順序・回数、失敗・再起動、引数、隔離したホームへのchezmoi適用、CI実行と削除先の境界。
- `TestRunner.Tests.ps1`: 必要module不在、0件・container失敗の検出。
- `Integration.Tests.ps1`: Windows profile、chezmoi反映とWSLg templateの描画。
- `lib/`: native実行、登録、同期、lock済み構成の反映の境界。

runtime suite はインストール済みの安定版 Pester 6.2 以降を使い、依存を自動取得しません。
formatter の実行・冪等性は Nix build check で確認します。
実インストール・ネットワーク・UACはmockし、実CLIは一時ホームに隔離します。
旧仕様、ソースの書き方、同一契約の重複検証は維持しません。

## CI

Lint 完了後に Windows Plan と WSL Build を独立して実行し、その成果物を Windows / WSL E2E が受け取ります。
更新対象の PowerShell 自身が終了しないよう、安定した 5.1 プロセスで先に runtime を準備し、
選択 runtime の installer 終了コードと import 完了を確認します。
runtime 準備用の一時 manifest は成功・失敗時とも削除します。
Taskfile が一時 distro の登録、prebuilt closure の import、本番 setup、cold restart、Hermes の health 検証と削除を順に実行します。
Pester suite は E2E 後に PowerShell 5.1 / 7 で runtime 契約を検証します。
