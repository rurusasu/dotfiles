BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

    function Assert-BootstrapBuildCompleteFailureGuard {
        param(
            [Parameter(Mandatory)]
            [string]$CompleteScript
        )

        $changesGuard = '(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\r?\n^[ \t]+echo "CI change detection did not complete successfully: \$\{CHANGES_RESULT\}"\r?\n^[ \t]+exit 1\r?\n^[ \t]+fi$'
        $platformDefault = '(?ms)^[ \t]+for result in "\$\{LINUX_RESULT\}" "\$\{DARWIN_RESULT\}"; do\r?\n^[ \t]+case "\$\{result\}" in\r?\n^[ \t]+success\|skipped\) ;;\r?\n^[ \t]+\*\)\r?\n^[ \t]+echo "Bootstrap platform job did not complete successfully: \$\{result\}"\r?\n^[ \t]+exit 1\r?\n^[ \t]+;;\r?\n^[ \t]+esac\r?\n^[ \t]+done$'

        if ($CompleteScript -notmatch $changesGuard) {
            throw 'Bootstrap Build complete job must exit 1 when change detection is not successful.'
        }

        if ($CompleteScript -notmatch $platformDefault) {
            throw 'Bootstrap Build complete job must exit 1 for every non-success-or-skipped platform result.'
        }
    }

    function Assert-ProtectedBootstrapE2ECompleteFailureGuard {
        param(
            [Parameter(Mandatory)]
            [string]$CompleteScript
        )

        $changesGuard = '(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\r?\n^[ \t]+echo "CI change detection did not complete successfully: \$\{CHANGES_RESULT\}"\r?\n^[ \t]+exit 1\r?\n^[ \t]+fi$'
        $platformDefault = '(?ms)^[ \t]+for result in "\$\{WINDOWS_RESULT\}" "\$\{MACOS_RESULT\}"; do\r?\n^[ \t]+case "\$\{result\}" in\r?\n^[ \t]+success\|skipped\) ;;\r?\n^[ \t]+\*\)\r?\n^[ \t]+echo "Hosted bootstrap platform job did not complete successfully: \$\{result\}"\r?\n^[ \t]+exit 1\r?\n^[ \t]+;;\r?\n^[ \t]+esac\r?\n^[ \t]+done$'

        if ($CompleteScript -notmatch $changesGuard) {
            throw 'Protected Bootstrap E2E complete job must exit 1 when change detection is not successful.'
        }

        if ($CompleteScript -notmatch $platformDefault) {
            throw 'Protected Bootstrap E2E complete job must exit 1 for every non-success-or-skipped platform result.'
        }
    }

    function Assert-UniqueChezmoiPathOccurrence {
        param(
            [Parameter(Mandatory)]
            [string]$Workflow,

            [Parameter(Mandatory)]
            [string]$LintJob
        )

        $normalizedWorkflow = $Workflow.ToLowerInvariant().Replace('\', '/')
        $normalizedLint = $LintJob.ToLowerInvariant().Replace('\', '/')
        $workflowOccurrences = ([regex]::Matches($normalizedWorkflow, [regex]::Escape('tests/chezmoi'))).Count
        $lintOccurrences = ([regex]::Matches($normalizedLint, [regex]::Escape('tests/chezmoi'))).Count
        if ($workflowOccurrences -ne 1) {
            throw "Chezmoi CI must contain exactly one tests/chezmoi path occurrence; found $workflowOccurrences."
        }
        if ($lintOccurrences -ne 1) {
            throw 'The unique tests/chezmoi path occurrence must belong to the lint job.'
        }
    }
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
        $workflow | Should -Match 'HEAD_REF:\s+\$\{\{ github\.head_ref \}\}'
        $workflow | Should -Match 'REF_NAME:\s+\$\{\{ github\.ref_name \}\}'
        $workflow | Should -Match '\$refName = \$env:HEAD_REF'
        $workflow | Should -Match '\$refName = \$env:REF_NAME'
        $workflow | Should -Not -Match '\$refName = "\$\{\{ github\.head_ref \}\}"'
        $workflow | Should -Match '\$distroName = "NixOS-CI-\$safeRef-\$refHash"'
        $workflow | Should -Not -Match '\$distroName = "NixOS-CI-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}"'
        $script | Should -Match '\$repoRoot = \(Resolve-Path -LiteralPath \(Join-Path \$PSScriptRoot "\.\.\\\.\.\\\.\."\)\)\.Path'
        $script | Should -Match 'SyncMode"\] = "repo"'
        $script | Should -Match 'SyncBack"\] = "none"'
        $script | Should -Not -Match 'SkipFlakeUpdate"\] = \$true'
        $script | Should -Match 'Welcome to your new NixOS-WSL system'
        $script | Should -Match 'nixos-rebuild list-generations'
        $workflow | Should -Match 'GITHUB_TOKEN:\s+\$\{\{ secrets\.GITHUB_TOKEN \}\}'
        $workflow | Should -Match 'WSLENV:\s+GITHUB_TOKEN/u'
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
        $powershellWorkflow | Should -Match '- name: Load Hermes bootstrap library on Windows PowerShell'
        $powershellWorkflow | Should -Match 'New-HermesBootstrapProcessStartInfo'
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

        $powershellWorkflow | Should -Match '"install\.cmd"'
        $powershellWorkflow | Should -Match '"docker/hermes-agent/\*\*"'
    }

    It 'should assign every Bats file to exactly one CI owner' {
        $contractWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-contract.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $contractWorkflow | Should -Match '"tests/bash/\*\*"'
        $contractWorkflow | Should -Match 'shopt -s nullglob'
        $contractWorkflow | Should -Match 'bats_files=\(tests/bash/\*\.bats\)'
        $contractWorkflow | Should -Match 'bats --print-output-on-failure "\$\{bats_files\[@\]\}"'

        $excludedBats = @('install_macos.bats', 'install_linux.bats')
        $allBats = Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'tests/bash') -Filter '*.bats' -File |
            Select-Object -ExpandProperty Name
        $allBats | Should -Contain 'ci_routing.bats'
        $contractExclusions = @(
            [regex]::Matches(
                $contractWorkflow,
                'tests/bash/(install_(?:macos|linux)\.bats)'
            ) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        )
        $contractExclusions.Count | Should -Be 2
        foreach ($excludedBat in $excludedBats) {
            $contractExclusions | Should -Contain $excludedBat
        }
        foreach ($batsFile in $allBats) {
            if ($batsFile -in $excludedBats) {
                $devcontainerWorkflow | Should -Match "tests/bash/$([regex]::Escape($batsFile))"
            }
            else {
                $contractWorkflow | Should -Match 'bats_files=\(tests/bash/\*\.bats\)'
            }
        }

        $excludedBats.Count | Should -Be 2
        $devcontainerWorkflow | Should -Match '"tests/bash/install_macos\.bats"'
        $devcontainerWorkflow | Should -Match '"tests/bash/install_linux\.bats"'
        $devcontainerWorkflow | Should -Not -Match '"tests/bash/\*\*"'
    }

    It 'should trigger PowerShell CI when Plane GitHub sync config changes' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $path = '- "chezmoi/dot_config/plane-github-sync/**"'
        ([regex]::Matches($powershellWorkflow, [regex]::Escape($path))).Count | Should -Be 2
    }

    It 'should trigger dcnvim platform tests when dcnvim implementations change' {
        $chezmoiWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-chezmoi.yml") -Raw
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $chezmoiWorkflow | Should -Match '"chezmoi/\*\*"'
        $chezmoiWorkflow | Should -Match '\.\\tests\\Invoke-Tests\.ps1 -Path \.\\tests\\chezmoi'
        $powershellWorkflow | Should -Match '"scripts/powershell/\*\*"'
        $devcontainerWorkflow | Should -Match '"scripts/sh/dcnvim\.sh"'
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

    It 'should build every declarative bootstrap output on hosted runners' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-build.yml"
        $workflowPath | Should -Exist
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should -Match 'name:\s+Bootstrap Build'
        $workflow | Should -Match 'timeout-minutes:'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'cachix/install-nix-action@[0-9a-f]{40}'
        $workflow | Should -Match 'darwinConfigurations\.macos\.system'
        $workflow | Should -Match 'systemConfigs\.ubuntu'
        $workflow | Should -Match 'systemConfigs\.debian'
        $workflow | Should -Match 'nixosConfigurations\.linux\.config\.system\.build\.toplevel'
        $workflow | Should -Match 'homeConfigurations\.x86_64-linux\.activationPackage'
        $workflow | Should -Match 'package-support-report'
    }

    It 'should route Bootstrap Build jobs through CI change detection without masking failures' {
        $workflowPath = Join-Path $script:repoRoot '.github/workflows/ci-bootstrap-build.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        foreach ($routingPath in @(
                'ci/path-routing.json',
                'scripts/python/detect_ci_changes.py',
                'tests/python/test_detect_ci_changes.py',
                '.github/actions/detect-ci-changes/**',
                '.github/workflows/ci-contract.yml',
                '.github/workflows/ci-bootstrap-build.yml'
            )) {
            ([regex]::Matches($workflow, [regex]::Escape($routingPath))).Count | Should -Be 2
        }

        $changesJob = [regex]::Match(
            $workflow,
            '(?ms)^  changes:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $changesJob | Should -Not -BeNullOrEmpty
        $changesJob | Should -Match 'fetch-depth:\s+0'
        $changesJob | Should -Match 'uses:\s+\./\.github/actions/detect-ci-changes'
        $changesJob | Should -Match 'steps\.detect\.outputs\.linux'
        $changesJob | Should -Match 'steps\.detect\.outputs\.darwin'
        $changesJob | Should -Match "github\.event_name == 'pull_request' && github\.event\.pull_request\.base\.sha"
        $changesJob | Should -Match 'github\.event\.before'
        $changesJob | Should -Match "github\.event_name == 'pull_request' && github\.event\.pull_request\.head\.sha"
        $changesJob | Should -Match 'github\.sha'
        $changesJob | Should -Match "run-all:\s+\$\{\{ github\.event_name == 'workflow_dispatch' \}\}"

        foreach ($gate in @(
                @{ Job = 'linux'; Output = 'linux' },
                @{ Job = 'darwin'; Output = 'darwin' }
            )) {
            $job = [regex]::Match(
                $workflow,
                "(?ms)^  $($gate.Job):\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)"
            ).Value
            $job | Should -Match 'needs:\s+changes'
            $job | Should -Match "needs\.changes\.outputs\.$($gate.Output) == 'true'"
        }

        $completeJob = [regex]::Match(
            $workflow,
            '(?ms)^  complete:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $completeJob | Should -Match 'if:\s+\$\{\{ always\(\) \}\}'
        $completeJob | Should -Match 'needs:\s+\[changes, linux, darwin\]'
        $completeJob | Should -Match 'needs\.changes\.result'
        $completeJob | Should -Match 'needs\.linux\.result'
        $completeJob | Should -Match 'needs\.darwin\.result'

        $completeScript = [regex]::Match(
            $completeJob,
            '(?ms)^      - name: Verify routed job results\r?\n        run: \|\r?\n(?<script>.*?^          echo "All required bootstrap outputs built successfully\."\r?\n)'
        ).Groups['script'].Value
        $completeScript | Should -Not -BeNullOrEmpty
        Assert-BootstrapBuildCompleteFailureGuard -CompleteScript $completeScript

        $changesGuard = [regex]::Match(
            $completeScript,
            '(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\r?\n.*?^[ \t]+fi$'
        ).Value
        $changesGuard | Should -Not -BeNullOrEmpty
        $withoutChangesGuard = $completeScript.Replace($changesGuard, '')
        { Assert-BootstrapBuildCompleteFailureGuard -CompleteScript $withoutChangesGuard } | Should -Throw

        $platformDefault = [regex]::Match(
            $completeScript,
            '(?ms)^[ \t]+\*\)\r?\n.*?^[ \t]+;;$'
        ).Value
        $platformDefault | Should -Not -BeNullOrEmpty
        $withoutPlatformDefault = $completeScript.Replace($platformDefault, '')
        { Assert-BootstrapBuildCompleteFailureGuard -CompleteScript $withoutPlatformDefault } | Should -Throw
    }

    It 'should run Ubuntu and Debian destructive installers twice with runtime acceptance' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-linux.yml"
        $workflowPath | Should -Exist
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should -Match 'name:\s+Ubuntu Destructive'
        $workflow | Should -Match 'name:\s+Debian systemd Destructive'
        $workflow | Should -Match 'timeout-minutes:'
        $workflow | Should -Match 'systemd-nspawn'
        $workflow | Should -Match '(?s)for _ in \$\(seq 1 60\).*machinectl shell.*systemctl is-system-running'
        $workflow | Should -Match 'dotfiles_run_in_group docker.*verify-environment\.sh --runtime'
        $workflow | Should -Match 'systemd systemd-sysv dbus'
        ([regex]::Matches($workflow, '(?m)^\s+- "flake\.nix"\s*$')).Count | Should -Be 2
        ([regex]::Matches($workflow, '(?m)^\s+- "flake\.lock"\s*$')).Count | Should -Be 2
        ([regex]::Matches($workflow, '(?m)^\s*\./\.github/e2e/run-bootstrap-acceptance\.sh\s*$')).Count | Should -BeGreaterOrEqual 2
        ([regex]::Matches($workflow, 'scripts/sh/verify-environment\.sh --runtime')).Count | Should -BeGreaterOrEqual 2
        $workflow | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
        $workflow | Should -Match 'if:\s+always\(\)'
    }

    It 'should run idempotent NixOS activation and Docker acceptance in a VM' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-linux.yml"
        $testPath = Join-Path $script:repoRoot "nix/tests/bootstrap-nixos.nix"
        $workflowPath | Should -Exist
        $testPath | Should -Exist
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $test = Get-Content -LiteralPath $testPath -Raw

        $workflow | Should -Match 'name:\s+NixOS VM'
        $workflow | Should -Match 'bootstrap-nixos-vm'
        $test | Should -Match 'dotfilesSource\s*=\s*\.\./\.\.'
        $test | Should -Match 'testScript\s*=\s*\{\s*nodes,\s*\.\.\.\s*\}:'
        $test | Should -Match 'DOTFILES_NIXOS_PREBUILT_SYSTEM=\$\{nodes\.machine\.system\.build\.toplevel\}'
        $test | Should -Match 'system\.switch\.enable\s*=\s*true'
        $test | Should -Match 'cp -r \$\{dotfilesSource\} /home/nixos/dotfiles'
        $test | Should -Match '/home/nixos/dotfiles/\.github/e2e/run-bootstrap-acceptance\.sh'
        $test | Should -Not -Match 'sg docker -c'
        ([regex]::Matches($test, 'machine\.succeed\(install\)')).Count | Should -Be 2
        $test | Should -Match 'verify-environment\.sh --runtime'
        $test | Should -Match 'docker/hermes-agent/compose\.yml'
        $test | Should -Match 'docker compose.*ps'
    }

    It 'should route Linux and WSL bootstrap E2E jobs through change detection without weakening fork protection' {
        $linuxWorkflowPath = Join-Path $script:repoRoot '.github/workflows/ci-bootstrap-e2e-linux.yml'
        $wslWorkflowPath = Join-Path $script:repoRoot '.github/workflows/ci-nixos-wsl.yml'
        $linuxWorkflow = Get-Content -LiteralPath $linuxWorkflowPath -Raw
        $wslWorkflow = Get-Content -LiteralPath $wslWorkflowPath -Raw

        foreach ($case in @(
                @{ Workflow = $linuxWorkflow; Path = 'ci-bootstrap-e2e-linux.yml'; Output = 'linux' },
                @{ Workflow = $wslWorkflow; Path = 'ci-nixos-wsl.yml'; Output = 'wsl' }
            )) {
            foreach ($routingPath in @(
                    'ci/path-routing.json',
                    'scripts/python/detect_ci_changes.py',
                    'tests/python/test_detect_ci_changes.py',
                    '.github/actions/detect-ci-changes/**',
                    '.github/workflows/ci-contract.yml',
                    ".github/workflows/$($case.Path)"
                )) {
                ([regex]::Matches($case.Workflow, [regex]::Escape($routingPath))).Count | Should -Be 2
            }

            $changesJob = [regex]::Match(
                $case.Workflow,
                '(?ms)^  changes:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
            ).Value
            $changesJob | Should -Not -BeNullOrEmpty
            $changesJob | Should -Match 'fetch-depth:\s+0'
            $changesJob | Should -Match 'uses:\s+\./\.github/actions/detect-ci-changes'
            $changesJob | Should -Match "steps\.detect\.outputs\.$($case.Output)"
            $changesJob | Should -Match "github\.event_name == 'pull_request' && github\.event\.pull_request\.base\.sha"
            $changesJob | Should -Match 'github\.event\.before'
            $changesJob | Should -Match "github\.event_name == 'pull_request' && github\.event\.pull_request\.head\.sha"
            $changesJob | Should -Match 'github\.sha'
            $changesJob | Should -Match "run-all:\s+\$\{\{ github\.event_name == 'workflow_dispatch' \}\}"
        }

        foreach ($jobName in @('ubuntu', 'debian', 'nixos')) {
            $job = [regex]::Match(
                $linuxWorkflow,
                "(?ms)^  ${jobName}:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)"
            ).Value
            $job | Should -Match 'needs:\s+changes'
            $job | Should -Match "needs\.changes\.outputs\.linux == 'true'"
        }

        $switchJob = [regex]::Match(
            $wslWorkflow,
            '(?ms)^  switch:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $switchJob | Should -Match 'needs:\s+changes'
        $switchJob | Should -Match "(?m)^\s+if:\s+\$\{\{ needs\.changes\.outputs\.wsl == 'true' && \(github\.event_name != 'pull_request' \|\| github\.event\.pull_request\.head\.repo\.full_name == github\.repository\) \}\}$"
        $switchJob | Should -Match 'HEAD_REF:\s+\$\{\{ github\.head_ref \}\}'
        $switchJob | Should -Match 'REF_NAME:\s+\$\{\{ github\.ref_name \}\}'
        $switchJob | Should -Match '\$refName = \$env:HEAD_REF'
        $switchJob | Should -Match '\$refName = \$env:REF_NAME'
        $switchJob | Should -Not -Match '\$refName = "\$\{\{ github\.head_ref \}\}"'
    }

    It 'should run bootstrap contracts exclusively on GitHub-hosted runners' {
        $oldWorkflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-self-hosted.yml"
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-hosted.yml"

        $oldWorkflowPath | Should -Not -Exist
        $workflowPath | Should -Exist

        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'name:\s+Protected Bootstrap E2E'
        $workflow | Should -Match 'runs-on:\s+windows-2025'
        $workflow | Should -Match 'runs-on:\s+macos-15'
        $workflow | Should -Match 'runs-on:\s+ubuntu-24\.04'
        $workflow | Should -Not -Match 'runs-on:\s*\[?self-hosted'
        $workflow | Should -Not -Match 'dotfiles-e2e'
        $workflow | Should -Not -Match 'destructive-e2e'
        $workflow | Should -Not -Match 'head\.repo\.full_name == github\.repository'
        $workflow | Should -Not -Match '(?m)^\s+paths:\s*$'
        $workflow | Should -Match 'permissions:\s*\r?\n\s+contents:\s+read'
        ([regex]::Matches($workflow, 'timeout-minutes:\s+30')).Count | Should -Be 2
        $workflow | Should -Match 'timeout-minutes:\s+5'
    }

    It 'should aggregate Windows and macOS contracts with explicit non-runtime attestations' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-hosted.yml"
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should -Match "Install-Module -Name Pester -RequiredVersion '5\.6\.1'"
        $workflow | Should -Match 'Invoke-Tests\.ps1 -MinimumCoverage 0 -OutputFile windows-contract-junit\.xml'
        $workflow | Should -Not -Match 'Invoke-Tests\.ps1[^\r\n]*-IncludeIntegration'
        $workflow | Should -Match 'brew install bash coreutils go-task lua'
        $workflow | Should -Match 'brew --prefix bash\)/bin'
        $workflow | Should -Match 'brew --prefix coreutils\)/libexec/gnubin'
        $workflow | Should -Match 'LC_ALL:\s+en_US\.UTF-8'
        $workflow | Should -Match 'bats(?: --print-output-on-failure)? tests/bash'
        $workflow | Should -Match 'nix build \.\#darwinConfigurations\.macos\.system --impure --no-link'
        ([regex]::Matches($workflow, 'runtime=not-applicable-on-github-hosted-runner')).Count | Should -Be 2
        $workflow | Should -Match '(?m)^  workflow_dispatch:\s*$'
        $workflow | Should -Match '(?ms)^  pull_request:\r?\n    branches: \[main\]\r?\n(?!    paths:)'
        $workflow | Should -Match 'protected-bootstrap-\$\{\{ github\.event\.pull_request\.number \|\| github\.ref \}\}'
        $workflow | Should -Match "TESTED_SHA:\s+\$\{\{ github\.event_name == 'pull_request' && github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}"
        $workflow | Should -Match 'needs:\s*\[changes, windows, macos\]'
        $workflow | Should -Match 'name:\s+Protected Bootstrap E2E'
        $workflow | Should -Match 'needs\.changes\.outputs\.windows == ''true'''
        $workflow | Should -Match 'needs\.changes\.outputs\.darwin == ''true'''
        $workflow | Should -Match 'fetch-depth:\s+0'
        $workflow | Should -Match 'uses:\s+\.\/\.github\/actions\/detect-ci-changes'
        $workflow | Should -Match 'run-all:\s+\$\{\{ github\.event_name == ''workflow_dispatch'' \}\}'
        $workflow | Should -Match 'needs\.windows\.result'
        $workflow | Should -Match 'needs\.macos\.result'
        $workflow | Should -Match 'needs\.changes\.result'
        ([regex]::Matches($workflow, 'ref:\s+\$\{\{ env\.TESTED_SHA \}\}')).Count | Should -Be 2
        ([regex]::Matches($workflow, 'actions/upload-artifact@[0-9a-f]{40}')).Count | Should -Be 2

        $completeJob = [regex]::Match(
            $workflow,
            '(?ms)^  complete:\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Groups['job'].Value
        $completeJob | Should -Not -BeNullOrEmpty
        $completeScript = [regex]::Match(
            $completeJob,
            '(?ms)^      - name: Verify routed job results\r?\n(?:        env:\r?\n.*?^        run: \|\r?\n)(?<script>.*?^          echo "All required hosted bootstrap contracts completed successfully\."\r?\n)'
        ).Groups['script'].Value
        $completeScript | Should -Not -BeNullOrEmpty
        Assert-ProtectedBootstrapE2ECompleteFailureGuard -CompleteScript $completeScript

        $changesGuard = [regex]::Match(
            $completeScript,
            '(?ms)^[ \t]+if \[\[ "\$\{CHANGES_RESULT\}" != "success" \]\]; then\r?\n.*?^[ \t]+fi$'
        ).Value
        $changesGuard | Should -Not -BeNullOrEmpty
        $withoutChangesGuard = $completeScript.Replace($changesGuard, '')
        { Assert-ProtectedBootstrapE2ECompleteFailureGuard -CompleteScript $withoutChangesGuard } | Should -Throw

        $platformDefault = [regex]::Match(
            $completeScript,
            '(?ms)^[ \t]+\*\)\r?\n.*?^[ \t]+;;$'
        ).Value
        $platformDefault | Should -Not -BeNullOrEmpty
        $withoutPlatformDefault = $completeScript.Replace($platformDefault, '')
        { Assert-ProtectedBootstrapE2ECompleteFailureGuard -CompleteScript $withoutPlatformDefault } | Should -Throw
    }

    It 'should run Hammerspoon syntax and behavioral contracts in the required macOS job' {
        $workflowPath = Join-Path $script:repoRoot '.github/workflows/ci-bootstrap-e2e-hosted.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $macosJob = [regex]::Match(
            $workflow,
            '(?ms)^  macos:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value

        $macosJob | Should -Not -BeNullOrEmpty
        $macosJob | Should -Match 'brew install bash coreutils go-task lua'
        $macosJob | Should -Not -Match 'bash scripts/sh/.*wezterm.*nightly'
        $macosJob | Should -Match 'brew install --cask wezterm@nightly'
        $macosJob | Should -Match 'command -v lua'
        $macosJob | Should -Match 'command -v luac'
        $macosJob | Should -Match 'command -v wezterm'
        $macosJob | Should -Match 'bats tests/wezterm'
        $macosJob | Should -Match 'luac -p chezmoi/terminals/hammerspoon/init\.lua'
        $macosJob | Should -Match 'lua tests/lua/hammerspoon_terminal_prefix_test\.lua'
        $macosJob | Should -Not -Match 'continue-on-error:\s*true'
        $macosJob | Should -Not -Match '(?:command -v (?:lua|luac).*(?:\|\| true)|if\s+command -v (?:lua|luac))'
        $macosJob.IndexOf('brew install bash bats-core coreutils go-task lua') |
            Should -BeLessThan $macosJob.IndexOf('luac -p chezmoi/terminals/hammerspoon/init.lua')
        $macosJob.IndexOf('brew install --cask wezterm@nightly') |
            Should -BeLessThan $macosJob.IndexOf('bats tests/wezterm')
    }

    It 'should install chezmoi before every Windows job that runs chezmoi template tests' {
        $workflowCases = @(
            @{ Path = '.github/workflows/ci-chezmoi.yml'; Job = 'lint'; TestMarker = '.\tests\Invoke-Tests.ps1' },
            @{ Path = '.github/workflows/ci-powershell.yml'; Job = 'test'; TestMarker = 'Invoke-Pester -Configuration' },
            @{ Path = '.github/workflows/ci-bootstrap-e2e-hosted.yml'; Job = 'windows'; TestMarker = 'Invoke-Tests.ps1' }
        )

        foreach ($case in $workflowCases) {
            $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot $case.Path) -Raw
            $job = [regex]::Match(
                $workflow,
                "(?ms)^  $($case.Job):\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)"
            ).Value

            $job | Should -Not -BeNullOrEmpty
            $job | Should -Match 'winget install --id twpayne\.chezmoi --exact'
            $job | Should -Match 'Get-Command chezmoi -ErrorAction Stop'
            $job | Should -Match 'Add-Content -LiteralPath \$env:GITHUB_PATH -Value \$chezmoiDirectory -Encoding utf8'
            $job.IndexOf('winget install --id twpayne.chezmoi --exact') |
                Should -BeLessThan $job.IndexOf($case.TestMarker)
        }
    }

    It 'should run Chezmoi Pester once in required lint and upload lint JUnit output' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-chezmoi.yml') -Raw
        $pesterInvocation = '(?m)^          \.\\tests\\Invoke-Tests\.ps1 -Path \.\\tests\\chezmoi -MinimumCoverage 0 -OutputFile chezmoi-test-results\.xml$'
        $lintJob = [regex]::Match(
            $workflow,
            '(?ms)^  lint:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value

        $lintJob | Should -Not -BeNullOrEmpty
        ([regex]::Matches($workflow, '(?m)^  test:\s*$')).Count | Should -Be 0
        Assert-UniqueChezmoiPathOccurrence -Workflow $workflow -LintJob $lintJob
        $lintJob | Should -Match $pesterInvocation
        $canonicalInvocation = '.\tests\Invoke-Tests.ps1 -Path .\tests\chezmoi -MinimumCoverage 0 -OutputFile chezmoi-test-results.xml'
        foreach ($alternateInvocation in @(
                "      - run: >-`r`n          Invoke-Pester -Path .\tests\CHEZMOI",
                '      - run: Invoke-Pester -Path ./tests/chezmoi'
            )) {
            $mutatedWorkflow = $workflow.Replace(
                $canonicalInvocation,
                "$canonicalInvocation`r`n$alternateInvocation"
            )
            $mutatedLintJob = [regex]::Match(
                $mutatedWorkflow,
                '(?ms)^  lint:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
            ).Value
            { Assert-UniqueChezmoiPathOccurrence -Workflow $mutatedWorkflow -LintJob $mutatedLintJob } | Should -Throw
        }

        foreach ($requiredJob in @(
                @{ Job = 'lint'; Name = 'Lint \(Pester chezmoi\)' },
                @{ Job = 'fmt'; Name = 'Format \(\.tmpl BOM check\)' },
                @{ Job = 'op-guard'; Name = 'Render guard \(op unauthenticated\)' }
            )) {
            $job = [regex]::Match(
                $workflow,
                "(?ms)^  $($requiredJob.Job):\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)"
            ).Value
            $job | Should -Not -BeNullOrEmpty
            $job | Should -Match "(?m)^    name: $($requiredJob.Name)$"
        }

        $fontInstallJob = [regex]::Match(
            $workflow,
            '(?ms)^  font-install:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $fontInstallJob | Should -Match '(?m)^    name: Font install smoke \(Windows\)$'
        $lintJob | Should -Match '(?ms)^      - name: Upload test results\r?\n        uses: actions/upload-artifact@[0-9a-f]{40}.*?\r?\n        if: always\(\)\r?\n        with:\r?\n          name: chezmoi-test-results\r?\n          path: scripts/powershell/chezmoi-test-results\.xml$'
    }

    It 'should use directory discovery when excluding Windows integration tests' {
        $runnerPath = Join-Path $script:repoRoot 'scripts/powershell/tests/Invoke-Tests.ps1'
        $runner = Get-Content -LiteralPath $runnerPath -Raw

        $runner | Should -Match '\$Path = @\(\$scriptRoot\)'
        $runner | Should -Match '\$pesterConfig\.Run\.ExcludePath = @\("\*\*/Integration\.Tests\.ps1"\)'
        $runner | Should -Match '(?s)Set-StrictMode -Off.*Invoke-Pester -Configuration \$pesterConfig'
    }
}
