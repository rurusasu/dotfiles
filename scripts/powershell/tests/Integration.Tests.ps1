#Requires -Module Pester

Describe 'Integration Verification - Windows Environment' {
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
        ) {
            $c = Get-Command -Name $_ -ErrorAction SilentlyContinue
            if ($null -eq $c) { throw "コマンド '$_' が見つかりません" }
            Write-Host "確認完了: '$_'"
        }
    }

    Context 'NixOS Verification' {
        It "should have <_> installed in NixOS" -ForEach @(
            'nvim'
            'wezterm'
            'zed'
            'task'
            'op'
        ) {
            $output = & wsl -d NixOS -- bash -lc "command -v $_"
            if ($LASTEXITCODE -ne 0) { throw "NixOS: '$_' が見つかりません" }
            Write-Host "NixOS: 確認完了 '$_' 場所: '$output'"
        }
    }
}
