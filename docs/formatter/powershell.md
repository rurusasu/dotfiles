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

## 文字コードと改行

`scripts/powershell/` 配下の非 ASCII ソース (`.ps1` / `.psm1` / `.psd1`) は
**UTF-8 BOM 付き、CRLF** で保存します。Windows PowerShell 5.1 は BOM がないと
システムの ANSI コードページで読み、日本語の閉じ引用符まで誤読する場合があります。
`chcp 65001` や `$OutputEncoding` では、このファイル読み込みの問題は解消しません。

[`.treefmt.toml`](../../.treefmt.toml) と
[`nix/flakes/treefmt.nix`](../../nix/flakes/treefmt.nix) は本文が変わらない場合も
必要な BOM を補い、既存 BOM を維持します。ASCII のみのファイルには必須ではありません。
`chezmoi/` テンプレートには BOM を追加しません。

pre-commit の `fix-byte-order-marker` は `scripts/powershell/` を除外し、
PSScriptAnalyzer の `PSUseBOMForUnicodeEncodedFile` は有効にします。
CP932 での文字列保持、5.1 の実ファイル読み込み、formatter の BOM 補完と冪等性は
[回帰テスト](../scripts/powershell/testing.md#windows-powershell-51-の文字コード回帰テスト) で検証します。

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
[IO.File]::WriteAllText((Join-Path $PWD "script.ps1"), $formatted, [Text.UTF8Encoding]::new($true))

# 静的解析（lint）
Invoke-ScriptAnalyzer -Path "script.ps1" -Settings "PSScriptAnalyzerSettings.psd1"

# 再帰的に解析
Invoke-ScriptAnalyzer -Path "." -Recurse -Settings "PSScriptAnalyzerSettings.psd1"
```

## treefmt 設定

`.treefmt.toml` と `nix/flakes/treefmt.nix` の PowerShell 定義を同時に更新します。
PSScriptAnalyzer は 1.22.0 に固定し、対象は `.ps1`、`.psm1`、`.psd1` です。
formatter は UTF-8 として読み、CRLF に正規化してから、対象パス・非 ASCII 文字・
既存 BOM をもとに出力形式を決めます。本文の差分だけでなく BOM 不足も書き込み条件です。

```bash
nix fmt
nix fmt -- --fail-on-change
```

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
