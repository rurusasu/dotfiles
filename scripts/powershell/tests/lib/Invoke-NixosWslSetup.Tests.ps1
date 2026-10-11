#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/Invoke-NixosWslSetup.ps1
}

Describe 'Invoke-NixosWslSetup' {
    It 'uses explicit path flake references before the first rebuild' {
        $context = [SetupContext]::new('D:\dotfiles')
        $context.DistroName = 'NixOS'
        $script:flakeUpdateCommand = ''
        $script:rebuildCommand = ''

        Mock Invoke-Wsl {
            param($Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments -contains 'wslpath') { return '/mnt/d/dotfiles' }
            $command = [string]$Arguments[-1]
            if ($command -match 'getent passwd') { return 'user:x:1000:100:/home/user:/bin/bash' }
            if ($command -match 'id -gn') { return 'users' }
            if ($command -match 'cat /etc/nixos/dotfiles\.json') { return '' }
            if ($command -match 'flake update --flake') { $script:flakeUpdateCommand = $command }
            if ($command -match 'nixos-rebuild switch') { $script:rebuildCommand = $command }
            return ''
        }

        Invoke-NixosWslSetup -Context $context

        $script:flakeUpdateCommand | Should -Match 'flake update --flake ''path:/mnt/d/dotfiles'''
        $script:rebuildCommand | Should -Match 'nixos-rebuild switch --flake ''path:/mnt/d/dotfiles#nixos'''
    }
}
