#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/Invoke-NixosWslSetup.ps1
}

Describe 'Invoke-NixosWslSetup' {
    BeforeEach {
        $script:context = [SetupContext]::new('D:\dotfiles')
        $script:context.DistroName = 'NixOS'
        $script:configuredUser = 'nixos'
        $script:existingConfiguredUser = 'nixos'
        $script:currentUser = 'nixos'
        $script:accountHome = $null
        $script:setupCommands = @()
        Mock Invoke-Wsl {
            param($Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments -contains 'wslpath') { return '/mnt/d/dotfiles' }
            if (($Arguments -contains 'id') -and ($Arguments -contains '-un')) { return $script:currentUser }
            $command = [string]$Arguments[-1]
            $script:setupCommands += $command
            if ($command -match 'eval --raw .*wsl.defaultUser') {
                if ($command -match "eval --raw 'path:/mnt/d/dotfiles#") { return $script:configuredUser }
                return $script:existingConfiguredUser
            }
            if ($command -match 'getent passwd') {
                $accountHome = if ($script:accountHome) { $script:accountHome } else { "/home/$script:currentUser" }
                return ('{0}:x:1000:100::{1}:/bin/bash' -f $script:currentUser, $accountHome)
            }
            if ($command -match 'id -gn') { return 'users' }
            return ''
        }
    }

    It 'uses explicit path flakes and the declared default user without identity metadata' {
        Invoke-NixosWslSetup -Context $script:context
        $commands = $script:setupCommands -join "`n"
        $commands | Should -Match "eval --raw 'path:/mnt/d/dotfiles#nixosConfigurations.nixos.config.wsl.defaultUser'"
        $commands | Should -Match "getent passwd 'nixos'"
        $commands | Should -Match "flake update --flake 'path:/mnt/d/dotfiles'"
        $commands | Should -Match "nixos-rebuild switch --flake 'path:/mnt/d/dotfiles#nixos'"
        $commands | Should -Not -Match 'dotfiles\.json|/var/lib/dotfiles/user'
    }

    It 'preserves an already configured custom WSL user' {
        $script:configuredUser = 'alice'
        $script:currentUser = 'alice'
        Invoke-NixosWslSetup -Context $script:context
        ($script:setupCommands -join "`n") | Should -Match "getent passwd 'alice'"
        ($script:setupCommands -join "`n") | Should -Match "nixos-rebuild switch"
    }

    It 'requires the official boot procedure before changing the default user' {
        $script:currentUser = 'alice'
        { Invoke-NixosWslSetup -Context $script:context } | Should -Throw '*nixos-rebuild boot*'
        ($script:setupCommands -join "`n") | Should -Not -Match 'nixos-rebuild switch|chown|ln -s'
    }

    It 'should use the independent WSL checkout declaration in none sync mode' {
        $script:context.Options['SyncMode'] = 'none'
        $script:context.Options['SyncBack'] = 'none'
        $script:currentUser = 'alice'
        $script:existingConfiguredUser = 'alice'
        $script:accountHome = '/srv/homes/alice'

        Invoke-NixosWslSetup -Context $script:context

        $commands = $script:setupCommands -join "`n"
        $commands | Should -Match "eval --raw 'path:/srv/homes/alice/\.dotfiles#nixosConfigurations.nixos.config.wsl.defaultUser'"
        $commands | Should -Not -Match "eval --raw 'path:/mnt/d/dotfiles#"
        $commands | Should -Match "flake update --flake 'path:/srv/homes/alice/\.dotfiles'"
        $commands | Should -Match "nixos-rebuild switch --flake 'path:/srv/homes/alice/\.dotfiles#nixos'"
        $commands | Should -Not -Match 'chown|ln -s|tar|cp --'
    }

    It 'should still require the boot procedure when the independent checkout changes the default user' {
        $script:context.Options['SyncMode'] = 'none'
        $script:context.Options['SyncBack'] = 'none'
        $script:currentUser = 'alice'
        $script:existingConfiguredUser = 'bob'

        { Invoke-NixosWslSetup -Context $script:context } | Should -Throw "*declared wsl.defaultUser 'bob'*"
        ($script:setupCommands -join "`n") | Should -Not -Match 'nixos-rebuild switch|chown|ln -s'
    }
}
