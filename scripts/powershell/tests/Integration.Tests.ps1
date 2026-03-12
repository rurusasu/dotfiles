#Requires -Module Pester

Describe 'Integration Verification - Windows Environment' {
    Context 'GUI Apps Installation' {
        It "should have <_> installed" -ForEach @(
            'Obsidian.Obsidian'
        ) {
            $result = & winget list --id $_ --accept-source-agreements 2>$null
            if ($LASTEXITCODE -ne 0) { throw "winget パッケージ '$_' がインストールされていません" }
            Write-Host "確認完了: '$_'"
        }
    }

    Context 'Dev Tools Installation' {
        It "should have <_> installed" -ForEach @(
            'antigravity'
            'gh'
            'rg'
            'fd'
            'eza'
            'fzf'
            'zoxide'
            'winget'
            'wezterm'
        ) {
            $c = Get-Command -Name $_ -ErrorAction SilentlyContinue
            if ($null -eq $c) { throw "コマンド '$_' が見つかりません" }
            Write-Host "確認完了: '$_'"
        }
    }

    Context 'NixOS Verification' {
        It "should have <_> installed in NixOS" -ForEach @(
            'nvim'
            'zed'
            'task'
            'op'
            'obsidian'
        ) {
            $output = & wsl -d NixOS -- bash -lc "command -v $_"
            if ($LASTEXITCODE -ne 0) { throw "NixOS: '$_' が見つかりません" }
            Write-Host "NixOS: 確認完了 '$_' 場所: '$output'"
        }
    }
}
