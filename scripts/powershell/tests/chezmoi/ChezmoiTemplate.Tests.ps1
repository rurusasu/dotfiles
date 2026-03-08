#Requires -Module Pester

<#
.SYNOPSIS
    chezmoi テンプレート (.tmpl) のバリデーションテスト

.DESCRIPTION
    AGENTS.md のルールに基づき、テンプレートの安全性を静的に検証する:
    - onepasswordRead は lookPath "op" でガードされているか
    - 主要テンプレートに必須セクションが含まれているか
#>

BeforeAll {
    $script:chezmoiRoot = Join-Path $PSScriptRoot "../../../../chezmoi"
    $script:templateFiles = Get-ChildItem -Path $script:chezmoiRoot -Filter "*.tmpl" -Recurse
}

Describe 'chezmoi テンプレート バリデーション' {
    Context 'onepasswordRead には lookPath "op" ガードが必須' {
        It 'すべての .tmpl ファイルで onepasswordRead が lookPath "op" でガードされていること' {
            $violations = @()

            foreach ($file in $script:templateFiles) {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $content) { continue }

                # onepasswordRead を含むがファイル全体に lookPath "op" が無い場合は違反
                if ($content -match 'onepasswordRead' -and $content -notmatch 'lookPath\s+"op"') {
                    $violations += $file.FullName
                }
            }

            $violations | Should -BeNullOrEmpty -Because (
                "AGENTS.md ルール: onepasswordRead を使う箇所は lookPath `"op`" でガードすること。" +
                " 違反ファイル: $($violations -join ', ')"
            )
        }

        It 'onepasswordRead の各呼び出しが個別に lookPath ブロック内にあること' {
            foreach ($file in $script:templateFiles) {
                $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
                if (-not $lines) { continue }

                $inOpGuard = $false
                $lineNum = 0

                foreach ($line in $lines) {
                    $lineNum++

                    if ($line -match '\{\{-?\s*if\s+lookPath\s+"op"') {
                        $inOpGuard = $true
                    }

                    if ($line -match 'onepasswordRead' -and -not $inOpGuard) {
                        "$($file.Name):$lineNum should be inside a lookPath `"op`" block" |
                            Should -BeNullOrEmpty
                    }

                    if ($line -match '\{\{-?\s*end\s*\}\}' -and $inOpGuard) {
                        $inOpGuard = $false
                    }
                }
            }
        }
    }

    Context 'Gemini settings.json テンプレートの必須セクション' {
        BeforeAll {
            $script:geminiTemplate = Join-Path $script:chezmoiRoot "dot_gemini/settings.json.tmpl"
        }

        It 'security.auth セクションが含まれていること' {
            $content = Get-Content -Path $script:geminiTemplate -Raw
            $content | Should -Match '"security"' -Because "Gemini CLI の OAuth 認証設定が必要"
            $content | Should -Match '"selectedType"' -Because "認証タイプの指定が必要"
        }
    }
}
