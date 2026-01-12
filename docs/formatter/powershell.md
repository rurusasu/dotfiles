# PowerShell フォーマット設定 (PSScriptAnalyzer)

[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) の `Invoke-Formatter` を使用して PowerShell ファイルをフォーマットします。

## 設定ファイル

[PSScriptAnalyzerSettings.psd1](../../scripts/powershell/PSScriptAnalyzerSettings.psd1)

```powershell
@{
    # 除外するルール
    ExcludeRules = @(
        # dot-source で読み込む型は静的解析で認識できないため除外
        'PSUseOutputTypeCorrectly',
        # BOM エンコーディングは UTF-8 (without BOM) でも問題ないため除外
        'PSUseBOMForUnicodeEncodedFile',
        # 外部コマンドラッパー関数では ShouldProcess は不要なため除外
        'PSUseShouldProcessForStateChangingFunctions'
    )

    # 重大度でフィルタリング
    Severity = @('Error', 'Warning')

    # 特定のルールの設定
    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            allowlist = @()
        }
    }
}
```

## フォーマットスタイル

PSScriptAnalyzer は以下のスタイルでフォーマットします：

| 項目       | スタイル                         |
| ---------- | -------------------------------- |
| インデント | 4スペース                        |
| 中括弧     | K&R スタイル（開き括弧は同じ行） |
| 空白       | 演算子の前後にスペース           |

### コード例

```powershell
# フォーマット後
function Get-Something {
    param(
        [string]$Name,
        [int]$Count = 10
    )

    if ($Name) {
        Write-Host "Name: $Name"
    } else {
        Write-Host "No name"
    }
}
```

## 除外ルール

| ルール                                        | 理由                                            |
| --------------------------------------------- | ----------------------------------------------- |
| `PSUseOutputTypeCorrectly`                    | dot-source で読み込む型は静的解析で認識できない |
| `PSUseBOMForUnicodeEncodedFile`               | UTF-8 (without BOM) で問題ない                  |
| `PSUseShouldProcessForStateChangingFunctions` | ラッパー関数では ShouldProcess 不要             |

## インストール

### Nix (推奨)

PowerShell 自体をインストール（PSScriptAnalyzer は PowerShell Gallery から取得）:

```bash
# nix profile (flakes)
nix profile install nixpkgs#powershell

# nix-env
nix-env -iA nixpkgs.powershell

# nix run (一時的)
nix run nixpkgs#powershell -- -c "Write-Host 'Hello'"
```

### PSScriptAnalyzer のインストール

```powershell
# PowerShell Gallery からインストール
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

## 使用方法

```powershell
# フォーマット（ファイル内容を変換）
$content = Get-Content -Raw -Path "script.ps1"
$formatted = Invoke-Formatter -ScriptDefinition $content
Set-Content -Path "script.ps1" -Value $formatted

# 静的解析（lint）
Invoke-ScriptAnalyzer -Path "script.ps1" -Settings "PSScriptAnalyzerSettings.psd1"

# 再帰的に解析
Invoke-ScriptAnalyzer -Path "." -Recurse -Settings "PSScriptAnalyzerSettings.psd1"
```

## .treefmt.toml 設定

```toml
[formatter.powershell]
command = "pwsh"
options = [
  "-NoProfile",
  "-Command",
  "& { $ErrorActionPreference = 'Stop'; if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber | Out-Null }; Import-Module PSScriptAnalyzer -Force; $content = Get-Content -Raw -LiteralPath $env:FILENAME; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8 }"
]
includes = ["*.ps1"]
```

## treefmt-nix 設定

PowerShell は treefmt-nix の programs に含まれていないため、カスタム設定が必要です。

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix) で設定:

```nix
{
  treefmt = {
    # Custom formatters not in treefmt-nix programs
    settings.formatter = {
      # PowerShell (no built-in support)
      powershell = {
        command = "${pkgs.powershell}/bin/pwsh";
        options = [
          "-NoProfile"
          "-Command"
          "& { $content = Get-Content -Raw -LiteralPath $env:FILENAME; Import-Module PSScriptAnalyzer -Force; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8 }"
        ];
        includes = [ "*.ps1" ];
      };
    };
  };
}
```

### treefmt-nix カスタムフォーマッター

treefmt-nix では `settings.formatter` を使用してカスタムフォーマッターを定義できます。

参考: [treefmt-nix README](https://github.com/numtide/treefmt-nix#custom-formatters)

## フォーマット vs リント

| ツール                  | 目的                 | コマンド     |
| ----------------------- | -------------------- | ------------ |
| `Invoke-Formatter`      | コードスタイルの統一 | フォーマット |
| `Invoke-ScriptAnalyzer` | コード品質チェック   | リント       |

## エディター設定

### VSCode / Cursor

拡張機能: [PowerShell](https://marketplace.visualstudio.com/items?itemName=ms-vscode.powershell)

```json
{
  "[powershell]": {
    "editor.defaultFormatter": "ms-vscode.powershell",
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "files.encoding": "utf8bom"
  },
  "powershell.scriptAnalysis.enable": true,
  "powershell.scriptAnalysis.settingsPath": "PSScriptAnalyzerSettings.psd1",
  "powershell.codeFormatting.preset": "OTBS",
  "powershell.codeFormatting.useCorrectCasing": true,
  "powershell.codeFormatting.trimWhitespaceAroundPipe": true,
  "powershell.codeFormatting.whitespaceBetweenParameters": true
}
```

### Zed

```json
{
  "languages": {
    "PowerShell": {
      "tab_size": 4,
      "formatter": "language_server"
    }
  }
}
```

## 参考リンク

- [PSScriptAnalyzer GitHub](https://github.com/PowerShell/PSScriptAnalyzer)
- [treefmt-nix カスタムフォーマッター](https://github.com/numtide/treefmt-nix#custom-formatters)
- [ルール一覧](https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Rules/README.md)
- [設定ファイルの書き方](https://github.com/PowerShell/PSScriptAnalyzer#settings-support-in-scriptanalyzer)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode.powershell)
