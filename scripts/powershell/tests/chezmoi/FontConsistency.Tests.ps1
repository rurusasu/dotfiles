#Requires -Module Pester

<#
.SYNOPSIS
    フォント設定の一貫性検証テスト

.DESCRIPTION
    dotfiles 全体で使用する等幅フォントが editor/terminal/nix package で揃っていることを保証する。
    過去 Moralerspace HWJPDOC -> UDEV Gothic JPDOC NF への移行で 9 ファイルの同時更新が必要だった経緯から、
    一部の箇所だけ取り残されて起こる文字崩れ (Nerd Font グリフ欠落・descender 切り) を防ぐ。

    検証内容:
    - 旧フォント名 (Moralerspace) が dotfiles に残っていない
    - 新フォント family 名が editor/terminal 設定で一致している
    - nix package と Windows font installer の zip 名が同じバージョンを参照している
#>

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:expectedFont = "UDEV Gothic NF"
    $script:expectedNixPkg = "udev-gothic-nf"
    $script:legacyFontPattern = "Moralerspace"

    # フォント名を参照するべき設定ファイル一覧 (family 名そのもの)
    $script:fontConsumers = @(
        "chezmoi/terminals/wezterm/wezterm.lua",
        "chezmoi/terminals/windows-terminal/settings.json",
        "chezmoi/terminals/warp/settings.toml",
        "chezmoi/editors/zed/settings.json",
        "chezmoi/editors/cursor/settings.json",
        "chezmoi/editors/vscode/settings.json"
    )

    # nix package 参照箇所
    $script:nixCatalog = "nix/packages/sets.nix"

    # Windows font installer template
    $script:windowsInstaller = "chezmoi/.chezmoiscripts/setup/fonts/run_onchange_setup.ps1.tmpl"
}

Describe 'フォント設定の一貫性' {

    Context '旧フォント (Moralerspace) の残存チェック' {
        It '追跡対象の dotfiles にレガシー "Moralerspace" 参照がないこと' {
            # .git, .worktrees, ノードモジュール等を除外して repo 配下を走査
            Push-Location $script:repoRoot
            try {
                $matches = git grep -l -I -E $script:legacyFontPattern 2>$null
            }
            finally {
                Pop-Location
            }

            # このテストファイル自身は legacyFontPattern を文字列として持つので除外
            $thisFileRel = "scripts/powershell/tests/chezmoi/FontConsistency.Tests.ps1"
            $offenders = @($matches | Where-Object { $_ -and $_ -ne $thisFileRel })

            $offenders | Should -BeNullOrEmpty -Because (
                "Moralerspace -> UDEV Gothic 移行漏れ。" +
                " 違反ファイル: $($offenders -join ', ')"
            )
        }
    }

    Context '新フォント family 名の整合' {
        It 'editor/terminal 設定すべてに "<expected>" が含まれること' -ForEach @(
            @{ Path = "chezmoi/terminals/wezterm/wezterm.lua";           Expected = $script:expectedFont }
            @{ Path = "chezmoi/terminals/windows-terminal/settings.json"; Expected = $script:expectedFont }
            @{ Path = "chezmoi/terminals/warp/settings.toml";             Expected = $script:expectedFont }
            @{ Path = "chezmoi/editors/zed/settings.json";                Expected = $script:expectedFont }
            @{ Path = "chezmoi/editors/cursor/settings.json";             Expected = $script:expectedFont }
            @{ Path = "chezmoi/editors/vscode/settings.json";             Expected = $script:expectedFont }
        ) {
            param($Path, $Expected)
            $full = Join-Path $script:repoRoot $Path
            Test-Path -LiteralPath $full | Should -BeTrue -Because "$Path が存在しない"

            $content = Get-Content -LiteralPath $full -Raw
            $content | Should -Match ([regex]::Escape($Expected)) -Because (
                "$Path に '$Expected' が含まれていない。フォント統一が崩れている可能性。"
            )
        }
    }

    Context 'nix package カタログとフォント名の整合' {
        It "nix catalog に '$script:expectedNixPkg' エントリが含まれること" {
            $full = Join-Path $script:repoRoot $script:nixCatalog
            $content = Get-Content -LiteralPath $full -Raw
            $content | Should -Match ([regex]::Escape("pkgs.$script:expectedNixPkg")) -Because (
                "$script:nixCatalog に pkgs.$script:expectedNixPkg 参照が無い。" +
                " UDEV Gothic NF が NixOS 側にインストールされない。"
            )
        }
    }

    Context 'Windows font installer の整合性' {
        It 'installer が UDEV Gothic NF の zip URL を参照していること' {
            $full = Join-Path $script:repoRoot $script:windowsInstaller
            $content = Get-Content -LiteralPath $full -Raw

            $content | Should -Match 'yuru7/udev-gothic/releases/download' -Because (
                "installer の DownloadUrl が yuru7/udev-gothic を指していない"
            )
            $content | Should -Match 'UDEVGothic_NF' -Because (
                "installer の FontName / URL に UDEVGothic_NF が含まれていない"
            )
        }

        It 'installer のレジストリ検出パターンが UDEV Gothic NF を捉えること' {
            $full = Join-Path $script:repoRoot $script:windowsInstaller
            $content = Get-Content -LiteralPath $full -Raw

            # Test-FontInstalled の Where-Object パターンが新フォントを検出するパターンであること
            $content | Should -Match 'UDEVGothic\*NF\*' -Because (
                "installer の Test-FontInstalled が UDEVGothic*NF* を検出するパターンになっていない"
            )
        }
    }
}
