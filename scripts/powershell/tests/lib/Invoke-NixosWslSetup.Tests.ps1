#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/Invoke-NixosWslSetup.ps1
}

Describe 'Install-NixosWsl' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $script:installDir = Join-Path $caseRoot 'NixOS'
        $script:previousTemp = $env:TEMP
        $script:previousTmp = $env:TMP
        $env:TEMP = $TestDrive
        $env:TMP = $TestDrive
        $script:wslCalls = [Collections.Generic.List[object]]::new()
        $script:releaseRequests = @()
        $script:downloadRequests = @()
        $script:downloadPath = $null
        $script:downloadExistedAtRegistration = $false
        $script:registeredDistros = @()
        $script:listExitCode = 0
        $script:registrationExitCode = 0
        $script:release = @{
            tag_name = 'fixture-release'
            assets = @(
                @{ name = 'nixos.aarch64.wsl'; browser_download_url = 'https://example.invalid/arm.wsl' }
                @{ name = 'nixos.wsl.sha256'; browser_download_url = 'https://example.invalid/checksum' }
                @{ name = 'nixos.wsl'; browser_download_url = 'https://example.invalid/nixos.wsl' }
            )
        }
        Mock Invoke-Wsl {
            param($Arguments)
            $script:wslCalls.Add(@($Arguments))
            if ($Arguments -contains '--list') {
                $global:LASTEXITCODE = $script:listExitCode
                return $script:registeredDistros
            }
            if ($script:downloadPath) {
                $script:downloadExistedAtRegistration = Test-Path -LiteralPath $script:downloadPath -PathType Leaf
            }
            $global:LASTEXITCODE = $script:registrationExitCode
            return 'registration output'
        }
        Mock Invoke-RestMethod {
            param($Uri)
            $script:releaseRequests += ([Uri]$Uri).AbsoluteUri
            return $script:release
        }
        Mock Invoke-WebRequest {
            param($Uri, $OutFile)
            $script:downloadRequests += [string]$Uri
            $script:downloadPath = $OutFile
            Set-Content -LiteralPath $OutFile -Value 'download fixture' -NoNewline
        }
    }

    AfterEach {
        $env:TEMP = $script:previousTemp
        $env:TMP = $script:previousTmp
    }

    It 'should leave an existing registration alone after stripping null bytes and BOM' {
        $script:registeredDistros = @((([char]0xFEFF).ToString() + " N`0i`0x`0O`0S`0 "), 'docker-desktop')

        Install-NixosWsl -DistroName 'NixOS' -InstallDir $script:installDir

        $script:wslCalls.Count | Should -Be 1
        ($script:wslCalls[0] -join '|') | Should -Be '--list|--quiet'
        $script:releaseRequests.Count | Should -Be 0
        $script:downloadRequests.Count | Should -Be 0
        Test-Path -LiteralPath $script:installDir | Should -Be $false
    }

    It 'should register the latest nixos.wsl once and remove only its unique download' {
        $unrelatedDownload = Join-Path $TestDrive 'nixos.wsl'
        Set-Content -LiteralPath $unrelatedDownload -Value 'keep me' -NoNewline

        Install-NixosWsl -DistroName 'NixOS' -InstallDir $script:installDir

        $script:releaseRequests | Should -Be @('https://api.github.com/repos/nix-community/NixOS-WSL/releases/latest')
        $script:downloadRequests | Should -Be @('https://example.invalid/nixos.wsl')
        $script:wslCalls.Count | Should -Be 2
        ($script:wslCalls[1] -join '|') | Should -Be "--install|--from-file|$script:downloadPath|--name|NixOS|--location|$script:installDir|--no-launch"
        [IO.Path]::GetFileName($script:downloadPath) | Should -Match '^nixos-[a-f0-9]{32}\.wsl$'
        $script:downloadExistedAtRegistration | Should -Be $true
        Test-Path -LiteralPath $script:downloadPath | Should -Be $false
        Get-Content -LiteralPath $unrelatedDownload -Raw | Should -Be 'keep me'
    }

    It 'should surface native installation failure and clean up the tagged release download' {
        $script:registrationExitCode = 17

        { Install-NixosWsl -InstallDir $script:installDir -ReleaseTag 'fixture/tag' } | Should -Throw '*nixos.wsl failed (exit=17)*'

        $script:releaseRequests | Should -Be @('https://api.github.com/repos/nix-community/NixOS-WSL/releases/tags/fixture%2Ftag')
        $script:wslCalls.Count | Should -Be 2
        $script:wslCalls[1][0] | Should -Be '--install'
        $script:downloadExistedAtRegistration | Should -Be $true
        Test-Path -LiteralPath $script:downloadPath | Should -Be $false
    }

    It 'should stop on a failed distribution query even when its output contains the name' {
        $script:registeredDistros = @('NixOS')
        $script:listExitCode = 5

        { Install-NixosWsl -InstallDir $script:installDir } | Should -Throw '*Could not list WSL distributions (exit=5)*'

        $script:wslCalls.Count | Should -Be 1
        $script:releaseRequests.Count | Should -Be 0
        $script:downloadRequests.Count | Should -Be 0
    }

    It 'should reject a release without nixos.wsl before downloading or registering' {
        $script:release.assets = @(
            @{ name = 'nixos-wsl.tar.gz' }
            @{ name = 'nixos.aarch64.wsl' }
            @{ name = 'nixos.wsl.sha256' }
        )

        { Install-NixosWsl -InstallDir $script:installDir -ReleaseTag 'fixture-release' } | Should -Throw '*Release fixture-release*nixos.wsl*ReleaseTag*'

        $script:releaseRequests | Should -Be @('https://api.github.com/repos/nix-community/NixOS-WSL/releases/tags/fixture-release')
        $script:downloadRequests.Count | Should -Be 0
        $script:wslCalls.Count | Should -Be 1
        Test-Path -LiteralPath $script:installDir | Should -Be $false
    }

    It 'should reject blank and occupied install directories without touching their contents' {
        { Install-NixosWsl -InstallDir '   ' } | Should -Throw '*must not be empty*'
        $script:wslCalls.Count | Should -Be 0
        New-Item -ItemType Directory -Path $script:installDir | Out-Null
        $protectedFile = Join-Path $script:installDir 'keep.txt'
        Set-Content -LiteralPath $protectedFile -Value 'protected' -NoNewline

        { Install-NixosWsl -InstallDir $script:installDir } | Should -Throw '*directory is not empty*'

        Get-Content -LiteralPath $protectedFile -Raw | Should -Be 'protected'
        $script:releaseRequests.Count | Should -Be 0
        $script:downloadRequests.Count | Should -Be 0
        $script:wslCalls.Count | Should -Be 1
    }

    It 'should recover the absolute VHD file in place and preserve it if registration fails' {
        New-Item -ItemType Directory -Path $script:installDir | Out-Null
        $vhdPath = Join-Path $script:installDir 'ext4.vhdx'
        Set-Content -LiteralPath $vhdPath -Value 'existing VHD' -NoNewline

        Install-NixosWsl -InstallDir $script:installDir
        ($script:wslCalls[1] -join '|') | Should -Be "--import-in-place|NixOS|$vhdPath"
        [IO.Path]::IsPathRooted($script:wslCalls[1][2]) | Should -Be $true
        $script:registrationExitCode = 9

        { Install-NixosWsl -InstallDir $script:installDir } | Should -Throw '*VHD registration failed (exit=9)*'

        ($script:wslCalls[3] -join '|') | Should -Be "--import-in-place|NixOS|$vhdPath"
        $script:wslCalls.Count | Should -Be 4
        Get-Content -LiteralPath $vhdPath -Raw | Should -Be 'existing VHD'
        @(Get-ChildItem -LiteralPath $script:installDir -Force).Count | Should -Be 1
        $script:releaseRequests.Count | Should -Be 0
        $script:downloadRequests.Count | Should -Be 0
    }
}

Describe 'Invoke-NixosWslSetup' {
    BeforeEach {
        $script:currentUser = 'nixos'
        $script:declaredUser = 'nixos'
        $script:sourcePath = '/mnt/d/dotfiles'
        $script:accountHome = '/home/nixos'
        $script:setupCommands = [Collections.Generic.List[string]]::new()
        $script:wslCalls = [Collections.Generic.List[object]]::new()
        Mock Invoke-Wsl {
            param($Arguments, $TimeoutSeconds)
            $script:wslCalls.Add(@{ Arguments = @($Arguments); TimeoutSeconds = $TimeoutSeconds })
            $global:LASTEXITCODE = 0
            if ($Arguments -contains 'wslpath') { return $script:sourcePath }
            if ($Arguments -contains '-un') {
                $executable = $Arguments[[Array]::IndexOf($Arguments, '--exec') + 1]
                if ($executable -ne '/run/current-system/sw/bin/id') {
                    throw "Default user lookup depends on inherited PATH: $executable"
                }
                return $script:currentUser
            }
            $command = [string]$Arguments[-1]
            $script:setupCommands.Add($command)
            if ($command -match 'eval --raw .*wsl.defaultUser') { return $script:declaredUser }
            if ($command -match 'getent passwd') {
                return ('{0}:x:1000:100::{1}:/bin/bash' -f $script:currentUser, $script:accountHome)
            }
            if ($command -match 'id -gn') { return 'users' }
            return ''
        }
    }

    It 'should quote paths and back up a conflicting link before updating and rebuilding once' {
        $script:currentUser = 'alice'
        $script:declaredUser = 'alice'
        $script:sourcePath = "/mnt/d/it's dotfiles"
        $script:accountHome = "/srv/homes/al'ice"

        Invoke-NixosWslSetup -Repository "D:\it's dotfiles" -DistroName 'NixOS' -ForcePostInstall -TimeoutSeconds 77

        $commands = $script:setupCommands -join "`n"
        $quotedRepo = "'/srv/homes/al'\''ice/.dotfiles'"
        $quotedSource = "'/mnt/d/it'\''s dotfiles'"
        $commands | Should -Match ([regex]::Escape("getent passwd 'alice'"))
        $commands | Should -Match ([regex]::Escape("mv -- $quotedRepo "))
        $commands | Should -Match ([regex]::Escape("ln -s -- $quotedSource $quotedRepo"))
        $commands | Should -Match ([regex]::Escape("chown -h -- 'alice:users'"))
        $commands | Should -Match ([regex]::Escape("flake update --flake 'path:/mnt/d/it'\''s dotfiles'"))
        $commands | Should -Match ([regex]::Escape("nixos-rebuild switch --flake 'path:/mnt/d/it'\''s dotfiles#nixos'"))
        @($script:setupCommands | Where-Object { $_ -match 'flake update --flake' }).Count | Should -Be 1
        @($script:setupCommands | Where-Object { $_ -match 'nixos-rebuild switch' }).Count | Should -Be 1
        @($script:wslCalls | Where-Object { $_.TimeoutSeconds -ne 77 }).Count | Should -Be 0
        $commands | Should -Not -Match 'dotfiles\.json|/var/lib/dotfiles/user|rm -rf'
    }

    It 'should validate the independent checkout user before any mutation in none sync mode' {
        $script:currentUser = 'alice'
        $script:declaredUser = 'bob'
        $script:accountHome = '/srv/homes/alice'

        { Invoke-NixosWslSetup -Repository 'D:\dotfiles' -SyncMode none -SyncBack none } | Should -Throw "*declared wsl.defaultUser 'bob'*nixos-rebuild boot*"

        $commands = $script:setupCommands -join "`n"
        $commands | Should -Match ([regex]::Escape("eval --raw 'path:/srv/homes/alice/.dotfiles#nixosConfigurations.nixos.config.wsl.defaultUser'"))
        $commands | Should -Not -Match "eval --raw 'path:/mnt/d/dotfiles#"
        $commands | Should -Not -Match 'nixos-rebuild switch|chown|ln -s|mv --|tar|flake update'

        $script:declaredUser = 'alice'
        $script:setupCommands.Clear()
        Invoke-NixosWslSetup -Repository 'D:\dotfiles' -SyncMode none -SyncBack none

        $commands = $script:setupCommands -join "`n"
        $commands | Should -Match ([regex]::Escape("flake update --flake 'path:/srv/homes/alice/.dotfiles'"))
        $commands | Should -Match ([regex]::Escape("nixos-rebuild switch --flake 'path:/srv/homes/alice/.dotfiles#nixos'"))
        @($script:setupCommands | Where-Object { $_ -match 'nixos-rebuild switch' }).Count | Should -Be 1
        $commands | Should -Not -Match 'chown|ln -s|mv --|tar|cp --'
    }

    It 'should synchronize a repository and its lock while rebuilding once without updating inputs' {
        Invoke-NixosWslSetup -Repository 'D:\dotfiles' -SyncMode repo -SyncBack lock -UpdateFlakeInputs $false

        $commands = $script:setupCommands -join "`n"
        $commands | Should -Match 'Existing checkout conflicts.*ForcePostInstall'
        $commands | Should -Match ([regex]::Escape("(cd '/mnt/d/dotfiles' && tar --exclude=.git --exclude=.direnv --exclude=result -cf - .) | (cd '/home/nixos/.dotfiles' && tar -xf -)"))
        $commands | Should -Match ([regex]::Escape("nixos-rebuild switch --flake 'path:/home/nixos/.dotfiles#nixos' --impure --no-update-lock-file"))
        $commands | Should -Match ([regex]::Escape("cp -- '/home/nixos/.dotfiles'/flake.lock '/mnt/d/dotfiles'/flake.lock"))
        @($script:setupCommands | Where-Object { $_ -match 'flake update --flake' }).Count | Should -Be 0
        @($script:setupCommands | Where-Object { $_ -match 'nixos-rebuild switch' }).Count | Should -Be 1
    }
}
