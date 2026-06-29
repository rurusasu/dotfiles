BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Describe 'CI workflow configuration' {
    It 'should install pinned PSScriptAnalyzer before nix fmt runs treefmt powershell formatter' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-nix.yml") -Raw

        $workflow | Should -Match 'name:\s+Install PSScriptAnalyzer'
        $workflow | Should -Match 'RequiredVersion 1\.22\.0'
        $workflow | Should -Match 'nix fmt -- --fail-on-change'
    }

    It 'should pin PSScriptAnalyzer used by treefmt powershell formatter' {
        $treefmtToml = Get-Content -LiteralPath (Join-Path $script:repoRoot ".treefmt.toml") -Raw
        $treefmtNix = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/flakes/treefmt.nix") -Raw

        $treefmtToml | Should -Match 'RequiredVersion 1\.22\.0'
        $treefmtToml | Should -Match 'Import-Module PSScriptAnalyzer -RequiredVersion 1\.22\.0'
        $treefmtNix | Should -Match 'RequiredVersion 1\.22\.0'
        $treefmtNix | Should -Match 'Import-Module PSScriptAnalyzer -RequiredVersion 1\.22\.0'
    }

    It 'should harden Windows PSScriptAnalyzer install against cache and gallery issues' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $workflow | Should -Match 'function Invoke-WithRetry'
        $workflow | Should -Match '\$env:PSModulePath = "\$moduleRoot;\$env:PSModulePath"'
        $workflow | Should -Match 'function Install-GalleryModuleArchive'
        $workflow | Should -Match 'https://www\.powershellgallery\.com/api/v2/package/\$Name/\$Version'
        $workflow | Should -Match "Install-GalleryModuleArchive -Name PSScriptAnalyzer -Version '1\.22\.0'"
        $workflow | Should -Match ([regex]::Escape('$_.RuleName -ne ''TypeNotFound'''))
        $workflow | Should -Not -Match 'Register-PSRepository -Default'
    }

    It 'should preserve CRLF and UTF-8 no BOM when treefmt formats PowerShell scripts' {
        $treefmtToml = Get-Content -LiteralPath (Join-Path $script:repoRoot ".treefmt.toml") -Raw
        $treefmtNix = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/flakes/treefmt.nix") -Raw

        foreach ($content in @($treefmtToml, $treefmtNix)) {
            $content | Should -Match '\[string\]\[char\]13 \+ \[string\]\[char\]10'
            $content | Should -Match '\[System\.IO\.File\]::WriteAllText'
            $content | Should -Match '\[System\.Text\.UTF8Encoding\]::new\(\$false\)'
            $content | Should -Match '\$args\.Count -gt 0'
            $content | Should -Match '\$args\[0\]'
            $content | Should -Match '\$normalized -ne \$raw'
            $content | Should -Not -Match 'Set-Content -LiteralPath \$env:FILENAME'
        }
    }

    It 'should run install.cmd in CI with timeout and completion marker checks' {
        $wingetWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-winget.yml") -Raw

        $wingetWorkflow | Should -Match '& cmd\.exe /d /c install\.cmd'
        $wingetWorkflow | Should -Match 'install\.cmd'
        $wingetWorkflow | Should -Match 'ForEach-Object'
        $wingetWorkflow | Should -Match '\$LASTEXITCODE'
        $wingetWorkflow | Should -Not -Match 'RedirectStandardOutput'
        $wingetWorkflow | Should -Match 'DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS:\s*"180"'
        $wingetWorkflow | Should -Match 'User Phase Complete!'
    }

    It 'should build the NixOS WSL system on hosted Nix CI' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-nix.yml") -Raw

        $nixWorkflow | Should -Match 'Build NixOS WSL system'
        $nixWorkflow | Should -Match 'nix build \.#nixosConfigurations\.nixos\.config\.system\.build\.toplevel --no-link'
    }

    It 'should build the font package set on hosted Nix CI' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-nix.yml") -Raw

        $nixWorkflow | Should -Match 'nix build \.#fonts'
    }

    It 'should free hosted runner disk space before Nix package builds' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-nix.yml") -Raw

        $nixWorkflow | Should -Match 'Free runner disk space'
        $nixWorkflow | Should -Match '/usr/share/dotnet'
        $nixWorkflow | Should -Match '/usr/local/lib/android'
        $nixWorkflow | Should -Match '/usr/local/share/boost'
        $nixWorkflow | Should -Match '/opt/ghc'
        $nixWorkflow | Should -Match '/opt/hostedtoolcache'
        $nixWorkflow | Should -Match 'docker image prune --all --force'
    }

    It 'should smoke test the Windows UDEV Gothic NF installer in chezmoi CI' {
        $chezmoiWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-chezmoi.yml") -Raw

        $chezmoiWorkflow | Should -Match 'Font install smoke \(Windows\)'
        $chezmoiWorkflow | Should -Match 'run_onchange_before_00-install-udev-gothic\.ps1\.tmpl'
        $chezmoiWorkflow | Should -Match '& pwsh -NoProfile -File \$scriptPath'
        $chezmoiWorkflow | Should -Match 'UDEVGothic\*NF\*'
        $chezmoiWorkflow | Should -Match 'Test-Path -LiteralPath \$fontPath -PathType Leaf'
        $chezmoiWorkflow | Should -Match 'needs: \[lint, fmt, font-install\]'
    }

    It 'should run nixos-rebuild switch in a hosted WSL2 E2E workflow' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-nixos-wsl.yml"
        $scriptPath = Join-Path $script:repoRoot "scripts/powershell/ci/Invoke-NixosWslE2E.ps1"
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $script = Get-Content -LiteralPath $scriptPath -Raw

        $workflow | Should -Match 'runs-on:\s+windows-2025'
        $workflow | Should -Match 'winget install --id Microsoft\.WSL --exact'
        $workflow | Should -Match 'wsl --set-default-version 2'
        $workflow | Should -Match 'Invoke-NixosWslE2E\.ps1'
        $workflow | Should -Match 'github\.event\.pull_request\.head\.repo\.full_name == github\.repository'
        $workflow | Should -Match '\$refName = "\$\{\{ github\.head_ref \}\}"'
        $workflow | Should -Match '\$distroName = "NixOS-CI-\$safeRef-\$refHash"'
        $workflow | Should -Not -Match '\$distroName = "NixOS-CI-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}"'
        $script | Should -Match '\$repoRoot = \(Resolve-Path -LiteralPath \(Join-Path \$PSScriptRoot "\.\.\\\.\.\\\.\."\)\)\.Path'
        $script | Should -Match 'SyncMode"\] = "repo"'
        $script | Should -Match 'SyncBack"\] = "none"'
        $script | Should -Not -Match 'SkipFlakeUpdate"\] = \$true'
        $script | Should -Match 'Welcome to your new NixOS-WSL system'
        $script | Should -Match 'nixos-rebuild list-generations'
        $script | Should -Match ([regex]::Escape('GH_TOKEN=ci TAVILY_API_KEY=ci GITHUB_WORK_TOKEN=ci zsh -ic "type z >/dev/null && bindkey"'))
        $script | Should -Match ([regex]::Escape('rg "\"\^\[q\" __zoxide_zi_widget"'))
        $script | Should -Not -Match ([regex]::Escape('rg "\"\^\[z\" __zoxide_zi_widget"'))
        $script | Should -Match 'Remove-TemporaryDistro'
    }

    It 'should cover Windows PowerShell 5.1 timeout wrapper compatibility in CI' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $windowsPowerShellInstall = [regex]::Match(
            $powershellWorkflow,
            '(?s)- name: Install Pester for Windows PowerShell.*?- name: Run Invoke-ExternalCommand tests on Windows PowerShell'
        ).Value

        $powershellWorkflow | Should -Match 'name:\s+Test \(Windows PowerShell 5\.1 compatibility\)'
        $powershellWorkflow | Should -Match 'shell:\s+powershell'
        $powershellWorkflow | Should -Match 'Get-Content -LiteralPath \.\\Invoke-Tests\.ps1 -Raw -Encoding UTF8'
        $powershellWorkflow | Should -Match '& \$runner -Path \.\\lib\\Invoke-ExternalCommand\.Tests\.ps1 -MinimumCoverage 0'
        $powershellWorkflow | Should -Not -Match '\$pesterConfig\.Filter\.FullName = "\*Invoke-VerifyCommand\*"'
        $windowsPowerShellInstall | Should -Match 'https://www\.powershellgallery\.com/api/v2/package/Pester/\$pesterVersion'
        $windowsPowerShellInstall | Should -Match 'Expand-Archive -LiteralPath \$packagePath -DestinationPath \$pesterPath'
        $windowsPowerShellInstall | Should -Match 'Import-Module Pester -RequiredVersion \$pesterVersion -Force'
        $windowsPowerShellInstall | Should -Not -Match 'Register-PSRepository'
        $windowsPowerShellInstall | Should -Not -Match 'Register-PSRepository -Default'
    }

    It 'should smoke test install.cmd when pwsh is absent from PATH' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $powershellWorkflow | Should -Match 'Run install\.cmd fallback without pwsh'
        $powershellWorkflow | Should -Match 'DOTFILES_PS7_DIR'
        $powershellWorkflow | Should -Match 'NoPowerShell7Dir'
        $powershellWorkflow | Should -Match '\$env:PATH = @\('
        $powershellWorkflow | Should -Match 'System32\\WindowsPowerShell\\v1\.0'
        $powershellWorkflow | Should -Match '& cmd\.exe /d /c install\.cmd -NoPause -UserPhaseOnly'
        $powershellWorkflow | Should -Match 'Falling back to Windows PowerShell'
        $powershellWorkflow | Should -Match 'User Phase Complete!'
    }

    It 'should retry winget source update when the runner reports Cancelled' {
        $wingetWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-winget.yml") -Raw

        $wingetWorkflow | Should -Match 'function Invoke-WingetSourceUpdate'
        $wingetWorkflow | Should -Match '\bCancelled\b'
        $wingetWorkflow | Should -Match 'winget source reset --force'
        $wingetWorkflow | Should -Match 'throw "winget source update did not complete after \$Attempts attempts"'
    }

    It 'should verify generated npm package catalog consistency' {
        $consistencyWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-consistency.yml") -Raw

        $consistencyWorkflow | Should -Match '"windows/npm/packages\.json"'
        $consistencyWorkflow | Should -Match '/tmp/winget-export/npm/packages\.json'
        $consistencyWorkflow | Should -Match 'windows/npm/packages\.json'
    }

    It 'should trigger entrypoint tests when install.cmd or bootstrap tests change' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $powershellWorkflow | Should -Match '"install\.cmd"'
        $powershellWorkflow | Should -Match '"docker/hermes-agent/\*\*"'
        $devcontainerWorkflow | Should -Match '"tests/bash/\*\*"'
    }

    It 'should trigger dcnvim platform tests when dcnvim implementations change' {
        $chezmoiWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-chezmoi.yml") -Raw
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $chezmoiWorkflow | Should -Match '"chezmoi/\*\*"'
        $chezmoiWorkflow | Should -Match '\$pesterConfig\.Run\.Path = "\./tests/chezmoi"'
        $powershellWorkflow | Should -Match '"scripts/powershell/\*\*"'
        $devcontainerWorkflow | Should -Match '"scripts/sh/dcnvim\.sh"'
        $devcontainerWorkflow | Should -Match '"tests/bash/\*\*"'
    }

    It 'should use a supported Intel macOS runner for devcontainer E2E' {
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $devcontainerWorkflow | Should -Match 'runs-on:\s+macos-15-intel'
        $devcontainerWorkflow | Should -Not -Match 'runs-on:\s+macos-13'
    }

    It 'should retry Linux devcontainer CLI install when Nix cache downloads fail' {
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $devcontainerWorkflow | Should -Match 'for attempt in 1 2 3'
        $devcontainerWorkflow | Should -Match "nix profile install 'nixpkgs#devcontainer'"
        $devcontainerWorkflow | Should -Match 'nix profile install devcontainer failed after \$attempt attempts'
        $devcontainerWorkflow | Should -Match 'retrying in \$\{sleep_seconds\}s'
    }
}
