# PowerShell テスト

## 全テストの実行

`tests/Invoke-Tests.ps1` を CI とローカルで共用します。既定では `tests/` 以下の
すべての `*.Tests.ps1` を検出し、`Integration.Tests.ps1` も実行します。
テストの除外や workflow ごとのテスト一覧はありません。0 件の検出、テスト・
container・block の失敗は失敗終了します。

```powershell
task test:powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1
```

個別の診断には `-Path`、カバレッジには `-ShowCoverage` / `-MinimumCoverage`、
JUnit 出力には `-OutputFile` を使います。カバレッジの既定値は 0 です。

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/handlers/Handler.Chezmoi.Tests.ps1
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -ShowCoverage -MinimumCoverage 80
```

## 前提と環境境界

ランナーと静的解析テストは、インストール済みの Pester / PSScriptAnalyzer から、現在の
PowerShell と互換性がある安定版の最高バージョンを使用します。必要な module がなければ、
事前準備を求めるエラーで終了します。Pester は 5.9 以上が必要です。
テスト中に PSGallery のバージョン照会、パッケージの
ダウンロード、インストールは行いません。
PowerShellGet / PackageManagement の暗黙の provider 導入やリポジトリ設定の更新も行いません。

テスト用の `USERPROFILE` / `LOCALAPPDATA` に切り替えるだけでは、HKCU の保存先は
隔離されません。User PATH の取得・保存は共通のモックで遮断し、保存動作を検証する
ケースだけがメモリー上の値へ差し替えます。子プロセスを使う fixture にも同じ境界を
設けます。環境変数は成功・失敗のどちらでも復元します。一時ディレクトリには、必要な
fixture と検証結果だけを作成します。本番 installer の自動取得処理は、通信と保存先を
fixture に置き換えて検証します。

Windows の全テストには、インストール済みで PATH から利用できる `task`、`winget`、
`pwsh`、`chezmoi`、`wezterm` が必要です。Task を含む CLI が不足する場合、テストは
自動取得せず、前提条件のエラーで終了します。CI の Windows installer matrix は PowerShell 5.1 / 7 の
それぞれで実際の `install.cmd -UserPhaseOnly` を適用した後に全スイートを実行します。
PowerShell 7 では同じ job で PSScriptAnalyzer も実行します。
installer E2E は追加されたコマンドパスを `GITHUB_PATH` に渡し、
テスト用の User PATH を復元した後も後続 step で実行ファイルを検出できるようにします。
workflow の構造やテストの配置先を Pester の文字列 assertion で固定しません。

GitHub hosted Windows runner は、イメージ作成時に Windows Update の接続制限と
`wuauserv` の無効化を設定しています。provisioner が開始時点までに設定を変更する
場合もあるため、CI は実行時の状態を確認します。WinGet の前に
`ci/Initialize-WindowsStore.ps1` で状態を表示し、Store のオンデマンド導入に必要な
接続とサービスを準備します。変更は2つの接続制限値と `wuauserv` に限定し、
`NoAutoUpdate` / `AUOptions` は保持・検証します。この初期化は GitHub hosted Windows
runner 以外では書き込み前にエラーにします。テストでは registry とサービスの操作を
メモリー上の fixture に差し替え、実環境を変更しません。
`-DiagnosticsOnly` は状態と直近の Store / Windows Update / AppX イベントを標準出力へ
表示し、診断用の `.log` は作りません。本文に詳細が表示されない Windows Update の
失敗は EventData も表示します。Store は直近500件から起点となる失敗を選び、
古い順に20件まで表示します。各 channel の直近20件の文脈も保持し、読み取り・表示の
上限到達を明示します。URL と認証情報に相当する値を伏せ、イベント内のフィールド数と
文字数も制限します。接続制限の存在だけで Store エラーの原因とは
断定せず、変更前後の状態と実際の installer 結果を確認します。
根拠は [runner image の設定](https://github.com/actions/runner-images/blob/aee0669dd04510a11756664eb77f5630debabed3/images/windows/scripts/build/Configure-System.ps1)
と [Microsoft の Store 接続に関する説明](https://learn.microsoft.com/en-us/windows/deployment/update/waas-manage-updates-wsus)です。

`Integration.Tests.ps1` は次を実コマンドで検証します。

- Windows が管理する4つの CLI の起動と終了コード。
- 一時 USERPROFILE と独立した chezmoi 設定・state を使った本物の `chezmoi apply`。
- 配布した設定の内容、配置ファイルの範囲、再適用時の冪等性。
- `NixOS` が存在する環境では、その distro 内の nvim / task / op / Obsidian。

Windows の検査は Windows 以外で skip します。NixOS の既存環境の検査は
`NixOS` distro がない環境で理由を付けて skip します。Windows installer job は
WSL distro を構築せず、使い捨て distro の導入・rebuild・Hermes service の
runtime 検証は同 workflow の WSL E2E が担当します。
削除した Windows CLI 設定やフォントの導入は現在の installer の検証対象に含めません。

## 維持する契約

- `Install.GuiOnly.Tests.ps1`: 実 entrypoint と本番 library に対し、WinGet 境界だけを fixture に置き換えた GUI 導入。
- `Install.Wsl.Tests.ps1`: 実 Taskfile / installer / NixOSWSL handler に対する再利用、新規導入、引数、失敗、再起動待ち。
- `tests/ci/`: installer の終了コード・完了証跡・パッケージ inventory・ログ取得の挙動。
- `PSScriptAnalyzer.Tests.ps1`: 現役 library / handler の Error と Warning。対象ゼロ・解析失敗も失敗。
- `WindowsPowerShell.Encoding.Tests.ps1`: 実 entrypoint と現役 handler の 5.1 読み込み、CP932 fallback での文字保持、formatter の BOM と冪等性。

Nix expression / option / package の値は `nix/tests/unit/` の nix-unit、ビルドと実行は
flake checks、shell / installer 境界は Bats が担当します。

## テストの実装

`It` 名は `should ...` で始め、関連ケースは `-ForEach` を使用します。
handler の単体テストでは外部コマンドの `Invoke-*` wrapper を mock し、
成功・失敗・適用できない条件を検証します。実 OS とコマンドの接続は integration / E2E で確認します。

PowerShell の formatter は `nix/formatter.nix` に宣言し、`nix fmt` から実行します。
`scripts/powershell/` の非 ASCII ソースは Windows PowerShell 5.1 用に UTF-8 BOM 付きで保存します。
詳細は [文字コード方針](../../formatter/powershell.md) を参照してください。
