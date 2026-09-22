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

# It -ForEach は Discovery フェーズで評価されるため、そこで参照する定数は
# BeforeDiscovery で設定する必要がある（BeforeAll は Run フェーズで遅すぎ、
# StrictMode 下では「変数未設定」で Discovery が失敗する）。
BeforeDiscovery {
    $script:expectedFont = "UDEV Gothic NF"
    $script:expectedNixPkg = "udev-gothic-nf"
}

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:expectedFont = "UDEV Gothic NF"
    $script:expectedNixPkg = "udev-gothic-nf"
    $script:legacyFontPattern = "Moralerspace"

    # フォント名を参照するべき設定ファイル一覧 (family 名そのもの)
    $script:fontConsumers = @(
        "chezmoi/terminals/wezterm/wezterm.lua",
        "chezmoi/terminals/windows-terminal/settings.json",
        "chezmoi/editors/zed/settings.json",
        "chezmoi/editors/cursor/settings.json",
        "chezmoi/editors/vscode/settings.json"
    )

    # nix package 参照箇所
    $script:nixCatalog = "nix/packages/sets.nix"

    # Windows font installer template
    $script:windowsInstallerDir = "chezmoi/.chezmoiscripts/setup/fonts"
    $script:windowsInstaller = "chezmoi/.chezmoiscripts/setup/fonts/run_onchange_before_00-install-udev-gothic.ps1.tmpl"
    $script:appearanceData = "chezmoi/.chezmoidata/appearance.json"
}

Describe 'フォント設定の一貫性' {

    Context '共通 appearance データ' {
        It 'should define the managed font and theme in one data file' {
            $full = Join-Path $script:repoRoot $script:appearanceData
            Test-Path -LiteralPath $full -PathType Leaf | Should -BeTrue
            $appearance = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json
            $appearance.appearance.font_family | Should -Be $script:expectedFont
            $appearance.appearance.font_release.archive_name | Should -Be 'UDEVGothic_NF'
            $appearance.appearance.font_release.version | Should -Match '^v\d+\.\d+\.\d+$'
            $appearance.appearance.theme | Should -Be 'Catppuccin Mocha'
        }

        It 'should make every terminal and editor consumer read the shared appearance data' {
            $consumers = @(
                "chezmoi/terminals/wezterm/wezterm.lua",
                "chezmoi/terminals/windows-terminal/settings.json",
                "chezmoi/terminals/ghostty/config",
                "chezmoi/editors/zed/settings.json",
                "chezmoi/editors/cursor/settings.json",
                "chezmoi/editors/vscode/settings.json"
            )
            foreach ($relativePath in $consumers) {
                $content = Get-Content -LiteralPath (Join-Path $script:repoRoot $relativePath) -Raw
                $content | Should -Match '\{\{\s*\.appearance\.font_family\s*\}\}' -Because $relativePath
                $content | Should -Match '\{\{\s*\.appearance\.theme\s*\}\}' -Because $relativePath
            }

            $windowsTerminal = Get-Content -LiteralPath (Join-Path $script:repoRoot 'chezmoi/terminals/windows-terminal/settings.json') -Raw
            $windowsTerminal | Should -Match '"size"\s*:\s*\{\{\s*\.appearance\.font_size\s*\}\}'
        }
    }

    Context '旧フォント (Moralerspace) の残存チェック' {
        It '追跡対象の dotfiles にレガシー "Moralerspace" 参照がないこと' {
            # .git, .worktrees, ノードモジュール等を除外して repo 配下を走査
            Push-Location $script:repoRoot
            try {
                # `$matches` は PowerShell の自動変数 (-match で書き込まれる) なので避ける
                $grepHits = git grep -l -I -E $script:legacyFontPattern 2>$null
            }
            finally {
                Pop-Location
            }

            # このテストファイル自身は legacyFontPattern を文字列として持つので除外
            $thisFileRel = "scripts/powershell/tests/chezmoi/FontConsistency.Tests.ps1"
            $offenders = @($grepHits | Where-Object { $_ -and $_ -ne $thisFileRel })

            $offenders | Should -BeNullOrEmpty -Because (
                "Moralerspace -> UDEV Gothic 移行漏れ。" +
                " 違反ファイル: $($offenders -join ', ')"
            )
        }
    }

    Context '新フォント family 名の整合' {
        It 'editor/terminal 設定すべてが共通 appearance の family を参照すること' -ForEach @(
            @{ Path = "chezmoi/terminals/wezterm/wezterm.lua" }
            @{ Path = "chezmoi/terminals/windows-terminal/settings.json" }
            @{ Path = "chezmoi/editors/zed/settings.json" }
            @{ Path = "chezmoi/editors/cursor/settings.json" }
            @{ Path = "chezmoi/editors/vscode/settings.json" }
        ) {
            param($Path)
            $full = Join-Path $script:repoRoot $Path
            Test-Path -LiteralPath $full | Should -BeTrue -Because "$Path が存在しない"

            $content = Get-Content -LiteralPath $full -Raw
            $content | Should -Match '\{\{\s*\.appearance\.font_family\s*\}\}' -Because (
                "$Path が共通 appearance.font_family を参照していない。フォント統一が崩れている可能性。"
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
        It 'installer は chezmoi apply のファイル更新前に実行されること' {
            $fullDir = Join-Path $script:repoRoot $script:windowsInstallerDir
            $installers = @(Get-ChildItem -LiteralPath $fullDir -Filter "run_*.ps1.tmpl" -File)

            $installers.Name | Should -Contain "run_onchange_before_00-install-udev-gothic.ps1.tmpl" -Because (
                "フォントは terminal/editor 設定より前に入れておくと初回 apply 中の後続処理で欠落しにくい"
            )
            $installers.Name | Should -Not -Contain "run_onchange_setup.ps1.tmpl" -Because (
                "before 属性なしの installer は chezmoi の通常エントリ順に依存する"
            )
        }

        It 'installer が UDEV Gothic NF の zip URL を参照していること' {
            $full = Join-Path $script:repoRoot $script:windowsInstaller
            $content = Get-Content -LiteralPath $full -Raw

            $content | Should -Match 'yuru7/udev-gothic/releases/download' -Because (
                "installer の DownloadUrl が yuru7/udev-gothic を指していない"
            )
            $content | Should -Match '\{\{\s*\.appearance\.font_release\.archive_name\s*\}\}' -Because (
                "installer の archive name は appearance data を参照する必要がある"
            )
            $content | Should -Match '\{\{\s*\.appearance\.font_release\.version\s*\}\}' -Because (
                "installer の version は appearance data を参照する必要がある"
            )
            $content | Should -Not -Match '\$FontVersion\s*=\s*"v\d+\.\d+\.\d+"' -Because (
                "installer に font version をハードコードすると chezmoi data と不一致になる"
            )
            $content | Should -Not -Match '\$FontName\s*=\s*"UDEVGothic_NF"' -Because (
                "installer に archive name をハードコードすると chezmoi data と不一致になる"
            )
        }

        It 'installer のインストール済み判定はレジストリと実ファイルの両方を確認すること' {
            $full = Join-Path $script:repoRoot $script:windowsInstaller
            $content = Get-Content -LiteralPath $full -Raw

            $content | Should -Match 'UDEVGothic\*NF\*' -Because (
                "installer の Test-FontInstalled が UDEVGothic*NF* を検出するパターンになっていない"
            )
            $content | Should -Match 'Test-Path -LiteralPath \$fontPath -PathType Leaf' -Because (
                "registry だけでなく実ファイルの存在も確認しないと、壊れたインストールを見逃す"
            )
            $content | Should -Match 'installation verification failed' -Because (
                "インストール後に registry/file の検証が失敗したら CI と chezmoi apply で失敗させる"
            )
            $content | Should -Match 'New-Item -Path \$RegistryPath -Force' -Because (
                "fresh user profile でも HKCU font registry path を作成できる必要がある"
            )
        }

        It 'installer の WM_FONTCHANGE 通知はハングしないよう timeout 付きで送ること' {
            $full = Join-Path $script:repoRoot $script:windowsInstaller
            $content = Get-Content -LiteralPath $full -Raw

            $content | Should -Match 'SendMessageTimeout' -Because (
                "HWND_BROADCAST への同期 SendMessage は応答しないウィンドウで install.cmd をハングさせる"
            )
            $content | Should -Match 'SMTO_ABORTIFHUNG' -Because (
                "応答しないウィンドウを待ち続けないフラグが必要"
            )
            $content | Should -Match '\$FontBroadcastTimeoutMilliseconds\s*=\s*[1-9]\d*' -Because (
                "timeout は 0 ではなく明示する"
            )
            $content | Should -Match '\[IntPtr\]0xffff' -Because (
                "HWND_BROADCAST は -1 ではなく Win32 の 0xffff を明示する"
            )
            $content | Should -Not -Match '::SendMessage\(' -Because (
                "timeout なしの同期 SendMessage は使用しない"
            )
        }
    }
}
