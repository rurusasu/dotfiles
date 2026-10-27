# Windows セットアップ

## 実装

`install.cmd` → `install.ps1` → WinGet master import → Taskfile の WSL → chezmoi の順です。
Taskもmasterから導入し、更新・反映は各1回です。
`-Phase Winget` / `Wsl` / `Chezmoi` はその操作だけを実行します。

実装は3ファイルです。

- `scripts/powershell/install.ps1`: Windowsの標準コマンドとTaskの起動、WSL基盤の昇格。
- `lib/Invoke-ExternalCommand.ps1`: native終了コード、timeout、UTF-8、PATH、標準import。
- `lib/Invoke-NixosWslSetup.ps1`: 必要時のdistro登録と、同期・input更新・NixOS/Home Manager反映。

通常の関数と例外を使います。クラス、結果オブジェクト、独自runnerはありません。
順序はTaskfileだけが管理し、初回導入と既存distroでsetupを重複させません。
WSL基盤だけを昇格し、成功後は3010で停止してWindows再起動を案内します。
Taskの194は3010に戻し、distro登録は元のユーザーで実行します。

WinGetは標準JSONをimportします。導入後にプロセスPATHを再読込し、Taskへ引き継ぎます。
開始時のPATHはcmd.exeの8191文字制限に収め、ユーザーPATHは変更しません。
chezmoiは`init --apply --force --no-tty --no-pager`を一度実行します。
WSL出力はUTF-8に統一し、日本語を含むチェックアウトパスも扱います。

既存VHDはファイルを指定して再登録し、非空の導入先は上書きしません。
競合するチェックアウトはForce指定時もGUID付きで退避します。
CIのdistroと削除先は`NixOS-CI-*`と一時領域の子ディレクトリに限定します。

旧構成の`install:windows` / `install:windows:post`は廃止しました。入口は`install.cmd`または`task install`です。
旧構成でPowerToysを導入した端末では、PowerToysを終了し、`winget uninstall --id Microsoft.PowerToys --exact --source winget`を一度手動で実行してください。
WinGet importは既存アプリを削除しません。旧PowerToysの設定JSONは変更せず、アプリの撤去によって以前のキー変換を停止します。

## テスト

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1
```

- `Install.Tests.ps1`: 実launcherとTaskfile、順序・回数、失敗・再起動、引数、隔離したホームへのchezmoi適用、CI実行と削除先の境界。
- `PowerShell.Tests.ps1`: runtime全体の静的解析とWindowsのANSI/BOM。formatterの実行・冪等性はNix build checkで確認します。
- `TestRunner.Tests.ps1`: 必要module不在、0件・container失敗の検出。
- `Integration.Tests.ps1`: Windows profile、chezmoi反映とWSLg templateの描画。
- `lib/`: native実行、登録、同期、更新と反映の境界。

インストール済みの安定版Pester 6.2以降とPSScriptAnalyzerを使い、依存を自動取得しません。
実インストール・ネットワーク・UACはmockし、実CLIは一時ホームに隔離します。
旧仕様、ソースの書き方、同一契約の重複検証は維持しません。

## CI

WindowsのStore準備とinstaller実行はworkflowに直接記載します。
更新対象のPowerShell自身が終了しないよう、安定した5.1プロセスで先にruntimeを準備し、選択runtimeのinstaller終了コードとimport完了を確認します。
runtime準備用の一時manifestは成功・失敗時とも削除します。
WSL E2Eもworkflowに記載します。一時distroの登録とprebuilt cache import後に本番と同じsetupを一度実行し、Hermesの再起動と認証を検証してdistroを削除します。
