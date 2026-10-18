# ハンドラー開発ガイド

## Windows セットアップのコマンド探索

通常の `install.cmd` は GUI アプリ導入後に NixOS-WSL を導入・設定します。`-UserPhaseOnly` は GUI のみです。`install.user.ps1` は引き続き `WingetHandler` だけを明示的にロードし、npm/pnpm/Bun・chezmoi・WSL/runtime acceptance は呼びません。GUI phase では退役パッケージの自動削除も無効です。

- エントリーポイントの `Repair-WindowsSetupEnvironment` は、既存の `%LOCALAPPDATA%\Microsoft\WindowsApps` が PATH から欠落していれば、現在のプロセスに補完する。これにより WinGet の実行エイリアスを事前確認で検出できる。
- `CanApply` が false の場合も、判定理由とスキップをログに表示する。検証に失敗した場合はコマンド・終了コード・出力を残す。
- PATH 修復の回帰テストは `tests/lib/WindowsSetupPath.Tests.ps1`。実際のコマンド探索と子プロセスでの検証を使い、外部インストールと永続設定変更はモックする。Windows 以外では明示的にスキップする。
- WinGet のコマンドリンクが欠落し `pathEntries` の明示設定もない場合は、対象 ID の WinGet パッケージディレクトリ内だけで検証コマンドと同名の exe を探す。候補が1件の場合に実体ディレクトリを PATH に追加し、DLL やデータファイルとの位置関係を保つ。候補が複数なら自動選択しない。
- GUI phase の PATH 修復は原則としてプロセス内に限定する。manifest の boolean `persistPathEntries: true` は宣言した `pathEntries` をユーザー PATH に保存する明示例外で、WSL の Git 状態取得の補助コマンドとして `Starship.Starship` と `Git.MinGit` が指定する。未指定・false は従来の動作を維持し、同じ directory を重複追加しない。回帰検証は `tests/handlers/Handler.Winget.PathPersistence.Tests.ps1` が mock のユーザー PATH store で行う。
- `verifyCommand.type: pathEntriesCommand` は宣言した `pathEntries` 内のコマンドだけを実行する。MinGit のように tree 全体が必要な package の実体を検証し、同名の別コマンドが PATH にあっても代替として使わない。回帰検証は `tests/handlers/Handler.Winget.PackagePathCommand.Tests.ps1` が担当する。

## WinGet の導入状態確認

WinGet の導入状態確認は、そのフェーズでインストールまたは検証するパッケージだけを対象にする。検証コマンドのない `skipInstall` パッケージと、管理者フェーズへ委譲した `Microsoft.WSL` には `winget list` を実行しない。検証付きの手動対象は、既存の検証を維持する。

## Discord の強制更新

`install.cmd` から呼ばれる WinGet ハンドラーは、`Discord.Discord` のインストール／更新前に `Invoke-DiscordInstallPreparation` で `%LOCALAPPDATA%\Discord` 配下の `Discord.exe` と `Update.exe` を強制終了し、各プロセスの終了を最大10秒待つ。Discord には `winget install --force` を使い、未インストール時も同じ install-or-upgrade 経路で処理する。Discord は実行時に強制終了されるため、未送信内容は事前に保存する。

別アプリの `Update.exe`、Discord Canary、別ユーザーの Discord は停止対象外。停止失敗時は Discord のインストーラーを起動せず、そのパッケージの失敗として報告し、残りのパッケージを続行する。`CanApply` と export はプロセスを停止しない。

## 新しいハンドラーの作成

テストは `tests/Invoke-Tests.ps1` から実行する。個別テストの失敗数だけでなく、Pester の discovery / container / block 失敗も非ゼロ終了にする。`TestRunnerFailures.Tests.ps1` は「正常なテスト + 読み込めないテスト」を子プロセスで実行し、成功扱いにならないことを確認する。CI では同じ suite を Windows PowerShell 5.1 と PowerShell 7 で実行する。

### ステップ 1: ハンドラーファイルの作成

**ファイル名**: `handlers/Handler.YourName.ps1`

**テンプレート**:

```powershell
using module ..\lib\SetupHandler.ps1

class YourNameHandler : SetupHandlerBase {
    YourNameHandler() {
        $this.Name = "YourName"
        $this.Description = "Your handler description"
        $this.Order = 50  # 既存ハンドラーの間に挿入する場合は 10 刻みで設定
    }

    [bool] CanApply([SetupContext]$context) {
        # 実行可否を判定
        # 例: 必要なファイルの存在確認、環境変数チェックなど
        $someFile = Join-Path $context.RootPath "some-file.txt"
        return (Invoke-TestPath $someFile)
    }

    [SetupResult] Apply([SetupContext]$context) {
        try {
            $this.WriteInfo("処理を開始します")

            # 外部コマンドはラッパー経由で実行（テスト可能）
            $output = Invoke-SomeCommand -ArgumentList "arg1", "arg2"

            # 共有データの設定（他のハンドラーで使用可能）
            $context.SharedData["YourName_Result"] = $output

            $this.WriteSuccess("処理が完了しました")
            return $this.CreateSuccessResult("成功: $output")

        } catch {
            $this.WriteError("エラーが発生しました: $($_.Exception.Message)")
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
```

### ステップ 2: 外部コマンドラッパーの追加（必要な場合）

**場所**: [lib/Invoke-ExternalCommand.ps1](../../../scripts/powershell/lib/Invoke-ExternalCommand.ps1)

```powershell
function Invoke-YourCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    & your-command.exe @ArgumentList
}
```

### ステップ 3: テストファイルの作成

**ファイル名**: `tests/handlers/Handler.YourName.Tests.ps1`

**テンプレート**（[テスト命名規則](testing.md#テスト命名規則ベストプラクティス) に準拠）:

```powershell
BeforeAll {
    . "$PSScriptRoot\..\..\lib\SetupHandler.ps1"
    . "$PSScriptRoot\..\..\lib\Invoke-ExternalCommand.ps1"
    . "$PSScriptRoot\..\..\handlers\Handler.YourName.ps1"
}

Describe 'YourNameHandler' {
    BeforeEach {
        $script:handler = [YourNameHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        # パラメタライズされたテスト（類似テストを -ForEach でまとめる）
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "YourName" }
            @{ property = "Description"; expected = "Your handler description" }
            @{ property = "Order"; expected = 50 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return true when file exists' {
            Mock Invoke-TestPath { return $true }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }

        It 'should return false when file does not exist' {
            Mock Invoke-TestPath { return $false }

            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        It 'should return success when command succeeds' {
            Mock Invoke-YourCommand { return "Success output" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "成功"
            Should -Invoke Invoke-YourCommand -Times 1 -Exactly
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-YourCommand { throw "Command failed" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

### ステップ 4: テスト実行とカバレッジ確認

```powershell
cd tests
.\Invoke-Tests.ps1 -Path .\handlers\Handler.YourName.Tests.ps1 -MinimumCoverage 0
```

### ステップ 5: 実行経路の明示

現在の `install.cmd` → `install.ps1` → `task install:windows` は、`taskfiles/install/taskfile.yml` の順序で `Invoke-WindowsInstallPhase.ps1 -Phase Gui`、`-Phase Wsl` を実行します。GUI は `install.user.ps1`、WSL は `WslInstallHandler` と `NixOSWSLHandler` を明示的に読み込みます。`Handler.*.ps1` を追加しても自動登録・実行されません。

### 実行経路と独立アダプター

WSL 基盤の有効化だけを `Invoke-WslBaseElevation` で UAC 昇格し、再起動後の再実行を案内します。distro の登録と設定適用は元のユーザーで実行します。新規導入では handler 内の設定適用を一度だけ実行し、既存 distro は `Invoke-NixosWslSetup` で更新します。GUI・WSL の失敗は非ゼロ終了になります。基盤有効化成功後の再起動待ちは例外にせず、installer が専用の終了コード `3010` を返します。どちらも `Setup Complete!` は表示しません。

旧管理者入口は復活させず、WSL 基盤専用の `WslBase` phase に限定します。`Invoke-WindowsInstallTask.ps1` は Task runtime の取得と configuration の子プロセスへの伝播を担当し、CLI の順序を重複定義しません。呼び出しごとの一時 result file で再起動待ちを受け取り、呼び出し元へ bool を返します。Task の標準出力は画面へ表示し、一時 result file は成功・失敗いずれも後片付けします。WSL の実環境検証は `ci/Invoke-NixosWslE2E.ps1` が担当します。

#### GUI-only の integration 契約

`Install.GuiOnly.Tests.ps1` は実物の `install.cmd -UserPhaseOnly` → `install.ps1` → `install.user.ps1` を一時ディレクトリで実行します。`SetupHandlerBase` / `SetupContext` / `SetupResult` とライブラリは本番ファイルを使用し、WinGet の外部インストール境界だけを決定的な fixture に置き換えます。

この契約は `-UserPhaseOnly` で GUI ハンドラーの成功・失敗、WinGet 不在時の失敗伝播、不要な admin / CLI / WSL / chezmoi コードを読み込まないことを確認します。成功時にだけ `User Phase Complete!` が出ます。`Install.Wsl.Tests.ps1` は実物の Taskfile と installer で既存・新規 distro、同期引数、失敗伝播、再起動待ちを検証します。`Install.Entrypoint.Tests.ps1` は実物の batch launcher の PowerShell 5.1 / 7 選択と引数伝播を検証します。

実 GUI アプリの WinGet 導入・検証は `Invoke-WindowsInstallerE2E.ps1` が担当し、CLI・WSL の導入は行いません。独立 WSL adapter と Unix の runtime 契約は別のテスト・E2E として維持します。

## ハンドラー開発のチェックリスト

### 必須要件

- [ ] ファイル名が `Handler.{Name}.ps1` パターンに一致している
- [ ] クラス名が `{Name}Handler` 形式である
- [ ] `SetupHandlerBase` を継承している
- [ ] `Order` プロパティが設定されている（10刻み推奨）
- [ ] `CanApply()` メソッドを実装している
- [ ] `Apply()` メソッドを実装している
- [ ] エラーハンドリングを実装している（try-catch）

### テスト要件

- [ ] テストファイルが `tests/handlers/Handler.{Name}.Tests.ps1` に存在する
- [ ] Constructor のテストがある
- [ ] CanApply() のテストがある（true/false両方）
- [ ] Apply() の成功ケースのテストがある
- [ ] Apply() の失敗ケースのテストがある
- [ ] 外部コマンドがすべてモックされている
- [ ] テストが 100% パスする

### コード品質

- [ ] 外部コマンドをラッパー経由で実行している
- [ ] 冪等性が保証されている（何度実行しても同じ結果）
- [ ] ログ出力を適切に使用している（WriteInfo/WriteSuccess/WriteError）
- [ ] SharedData を適切に使用している（必要な場合）
- [ ] パス操作に Join-Path を使用している

## 現役ハンドラー

| Handler             | 役割                                             |
| ------------------- | ------------------------------------------------ |
| `WingetHandler`     | Windows manifest のインストール・PATH 回復・検証 |
| `WslInstallHandler` | WSL コンポーネントの有効化、昇格・再起動の通知   |
| `NixOSWSLHandler`   | distro 初期化・初回同期、既存 distro の再利用    |
| `ChezmoiHandler`    | chezmoi の初期化・Windows 設定適用               |

`lib/SetupHandler.ps1` の型を読み込んでから必要な handler を呼び出し元で
明示的に dot-source します。実行順序は Taskfile で管理し、新しい handler を
ディレクトリに置いても自動では実行しません。通常の NixOS rebuild は `nrs`
タスクが担当します。CI の WSL E2E も同じ公開タスクを使用します。

[テスト方針](./testing.md) / [コーディング規約](./coding-standards.md)
