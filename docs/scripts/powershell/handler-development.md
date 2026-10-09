# ハンドラー開発ガイド

## Windows セットアップのコマンド探索

通常の `install.cmd` は GUI-only です。`install.user.ps1` は `WingetHandler` だけを明示的にロードし、npm/pnpm/Bun・CLI bootstrap・chezmoi・管理者フェーズ・WSL/runtime acceptance は呼びません。CLI の利用可能性と任意 adapter のテストは維持しますが、これらは通常の Windows セットアップの依存ではありません。GUI-only では退役パッケージの自動削除も無効です。

- エントリーポイントの `Repair-WindowsSetupEnvironment` は、既存の `%LOCALAPPDATA%\Microsoft\WindowsApps` が PATH から欠落していれば、現在のプロセスに補完する。これにより WinGet の実行エイリアスを事前確認で検出できる。
- npm / pnpm の `Apply` は `Update-NpmGlobalCommandPath` を呼ぶ。`npm prefix -g` が返す保存先を現在の PATH に補完してから、検証・bootstrap・インストールを行う。既定の `%APPDATA%\npm` に固定せず、カスタム prefix も扱う。
- prefix の取得結果は同じ `SetupContext.Options` 内で共有し、npm と pnpm で重複して問い合わせない。永続 USER PATH は書き換えない。
- `CanApply` が false の場合も、判定理由とスキップをログに表示する。検証に失敗した場合はコマンド・終了コード・出力を残す。
- PATH 修復の回帰テストは `tests/lib/WindowsSetupPath.Tests.ps1`。実際のコマンド探索と子プロセスでの検証を使い、外部インストールと永続設定変更はモックする。Windows 以外では明示的にスキップする。
- WinGet のコマンドリンクが欠落し `pathEntries` の明示設定もない場合は、対象 ID の WinGet パッケージディレクトリ内だけで検証コマンドと同名の exe を探す。候補が1件の場合に実体ディレクトリを PATH に追加し、DLL やデータファイルとの位置関係を保つ。候補が複数なら自動選択しない。
- `ci/Assert-WingetCommandRecovery.ps1` は任意の CLI 構成用に保持します。GUI-only E2E からは呼びません。検証専用の `EnsureProcessPathEntries` は永続 PATH を変更せず、終了時には呼び出し元の PATH を復元します。
- `tests/ci/Assert-WingetCommandRecovery.Tests.ps1` は旧 CLI probe が GUI manifest に混入しないことと、fixture に対する PATH 復旧・欠落/複数候補/検証失敗の契約を検査します。

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

現在の `install.cmd` → `install.ps1` → `install.user.ps1` は、GUI 専用の `WingetHandler` だけを明示的に読み込みます。`Handler.*.ps1` を追加しても自動登録・実行されません。CLI・WSL・自動設定配布のハンドラーは既定経路に追加しません。

### 実行経路と独立アダプター

Windows の既定経路には npm / pnpm / WSL / chezmoi / runtime acceptance の phase や UAC 昇格処理はありません。実行可能な WinGet がない場合、または GUI 導入に失敗した場合は非ゼロ終了になります。

`install.admin.ps1` は独立アダプターとして保持していますが、`install.cmd` は呼び出しません。明示的な呼び出しでは従来の `-AdminOnly` によるハンドラー選択を維持します。

#### GUI-only の integration 契約

`Install.GuiOnly.Tests.ps1` は実物の `install.cmd` → `install.ps1` → `install.user.ps1` を一時ディレクトリで実行します。`SetupHandlerBase` / `SetupContext` / `SetupResult` とライブラリは本番ファイルを使用し、WinGet の外部インストール境界だけを決定的な fixture に置き換えます。

この契約は GUI ハンドラーの成功・失敗、WinGet 不在時の失敗伝播、不要な admin / CLI / WSL / chezmoi コードを読み込まないことを確認します。成功時にだけ `Setup Complete!` が出ます。`Install.Entrypoint.Tests.ps1` は実物の batch launcher の PowerShell 5.1 / 7 選択と引数伝播を検証します。

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

## ハンドラーが動的ロードされない場合

### チェック項目

1. **ファイル名パターン**: `Handler.*.ps1` に一致しているか

   ```powershell
   # ✅ 正しい
   Handler.Docker.ps1

   # ❌ 誤り
   docker-handler.ps1
   MyHandler.ps1
   ```

2. **クラス名パターン**: `{Name}Handler` に一致しているか

   ```powershell
   # ✅ 正しい（Handler.Docker.ps1 の場合）
   class DockerHandler : SetupHandlerBase { }

   # ❌ 誤り
   class Docker : SetupHandlerBase { }
   class HandlerDocker : SetupHandlerBase { }
   ```

3. **基底クラス継承**: `SetupHandlerBase` を継承しているか

   ```powershell
   # ✅ 正しい
   class DockerHandler : SetupHandlerBase { }

   # ❌ 誤り
   class DockerHandler { }
   ```

4. **Order プロパティ**: コンストラクタで設定されているか

   ```powershell
   # ✅ 正しい
   DockerHandler() {
       $this.Order = 20
   }

   # ❌ 誤り（Order が未設定）
   DockerHandler() {
       $this.Name = "Docker"
   }
   ```

## 実装例

### 既存ハンドラーの参考実装

| ハンドラー   | ソースファイル                                                                            | テストファイル                                                                                              | 説明                   |
| ------------ | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---------------------- |
| Winget       | [Handler.Winget.ps1](../../../scripts/powershell/handlers/Handler.Winget.ps1)             | [Handler.Winget.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Winget.Tests.ps1)             | winget パッケージ管理  |
| Chezmoi      | [Handler.Chezmoi.ps1](../../../scripts/powershell/handlers/Handler.Chezmoi.ps1)           | [Handler.Chezmoi.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Chezmoi.Tests.ps1)           | dotfiles 適用          |
| WslConfig    | [Handler.WslConfig.ps1](../../../scripts/powershell/handlers/Handler.WslConfig.ps1)       | [Handler.WslConfig.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.WslConfig.Tests.ps1)       | .wslconfig 適用        |
| VhdManager   | [Handler.VhdManager.ps1](../../../scripts/powershell/handlers/Handler.VhdManager.ps1)     | [Handler.VhdManager.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.VhdManager.Tests.ps1)     | VHD 拡張、FS リサイズ  |
| Docker       | [Handler.Docker.ps1](../../../scripts/powershell/handlers/Handler.Docker.ps1)             | [Handler.Docker.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.Docker.Tests.ps1)             | Docker Desktop 連携    |
| VscodeServer | [Handler.VscodeServer.ps1](../../../scripts/powershell/handlers/Handler.VscodeServer.ps1) | [Handler.VscodeServer.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.VscodeServer.Tests.ps1) | VS Code Server 管理    |
| NixOSWSL     | [Handler.NixOSWSL.ps1](../../../scripts/powershell/handlers/Handler.NixOSWSL.ps1)         | [Handler.NixOSWSL.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.NixOSWSL.Tests.ps1)         | NixOS-WSL インストール |
| NixRebuild   | [Handler.NixRebuild.ps1](../../../scripts/powershell/handlers/Handler.NixRebuild.ps1)     | [Handler.NixRebuild.Tests.ps1](../../../scripts/powershell/tests/handlers/Handler.NixRebuild.Tests.ps1)     | NixOS 設定適用         |

`NixRebuild` は NixOS 内に直接導入された Hermes service/CLI も、解決した Linux user で検証する。
Windows 側に Hermes 専用ハンドラーは置かない。`Docker` の WSL 連携は
`EnableDockerDesktopIntegration = $true` を明示した場合だけ実行し、NixOS の必須処理にしない。
Docker VHDX 拡張は `ExpandDockerVhd = $true` で個別に選択する。

ハンドラーファイルの helper function をクラスメソッドが使う場合、entrypoint の script scope
で dot-source してから `Get-SetupHandler -SkipLoad` で生成する。loader の function scope
だけで読み込むと、loader から戻った後に helper が見つからなくなる。

### 関連ドキュメント

- [テスト](testing.md) - Pester v5 の使用方法とテストパターン
- [アーキテクチャ](../../architecture.md) - ハンドラーシステムの設計と実行フロー
- [コーディング規約](coding-standards.md) - 命名規則、スタイル、ベストプラクティス
