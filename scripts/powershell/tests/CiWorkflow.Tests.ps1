BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

    function Get-CiJobPattern {
        param([string]$Output)
        $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'ci/job-path-routing.json') -Raw | ConvertFrom-Json
        $manifest.rules | Where-Object { $Output -in $_.outputs } | ForEach-Object { $_.patterns }
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
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

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

    It 'should run install.cmd in CI with timeout and completion marker checks' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1") -Raw -Encoding UTF8
        $wingetAssertion = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/ci/Assert-WingetInstallSuccess.ps1") -Raw

        $installerScript | Should -Match '& cmd\.exe /d /c install\.cmd'
        $installerScript | Should -Match 'install\.cmd'
        $installerScript | Should -Match 'ForEach-Object'
        $installerScript | Should -Match '\$LASTEXITCODE'
        $installerScript | Should -Not -Match 'RedirectStandardOutput'
        $workflow | Should -Match 'DOTFILES_INSTALL_TIMEOUT_SECONDS:\s*"900"'
        $installerScript | Should -Match 'User Phase Complete!'
        $installerScript | Should -Match 'Get-Command -Name \$runtimeCommand -CommandType Application -ErrorAction Stop'
        $installerScript | Should -Match "DOTFILES_FORCE_WINDOWS_POWERSHELL = '1'"
        $installerScript | Should -Not -Match 'NoPowerShell7Dir|where\.exe pwsh\.exe'
        $installCmd = Get-Content -LiteralPath (Join-Path $script:repoRoot 'install.cmd') -Raw
        $installCmd | Should -Match 'DOTFILES_FORCE_WINDOWS_POWERSHELL'
        $installerScript | Should -Match 'The full Windows installer E2E did not exercise the forced Windows PowerShell 5\.1 path'
        $installerScript | Should -Match 'oversizedUserPathEntries = 1\.\.1000'
        $installerScript | Should -Match 'install\.cmd invokes chcp before PowerShell can normalize the environment'
        $installerScript | Should -Match 'Process PATH normalized: removed'
        $installerScript | Should -Match 'missing directories and omitted.*final length.*8191'
        $installerScript | Should -Match 'seededUserPath\.Length -le 32767'
        $installerScript | Should -Match 'Registry\]::CurrentUser\.OpenSubKey\(''Environment'', \$true\)'
        $installerScript | Should -Match 'SetValue\(''PATH'', \$seededUserPath, \[Microsoft\.Win32\.RegistryValueKind\]::ExpandString\)'
        $installerScript | Should -Match 'User PATH repaired: removed'
        $installerScript | Should -Match 'remainingStaleUserPathEntries'
        $installerScript | Should -Match 'DoNotExpandEnvironmentNames'
        $installerScript | Should -Match 'SetValue\(''PATH'', \$originalUserPathRegistryValue, \$originalUserPathRegistryKind\)'
        $installerScript | Should -Match 'DeleteValue\(''PATH'', \$false\)'
        $installerScript | Should -Match 'User PATH cleanup:'
        $installerScript | Should -Match 'Assert-WingetInstallSuccess -Output \$out'
        $installerScript | Should -Match 'Assert-WingetInstallSuccess\.ps1'
        $installerScript | Should -Match 'Assert-WingetInstallSuccess -Output \$out -ExpectedPackageIds \$expectedWindowsPackageIds'
        $installerScript | Should -Match '\$wingetManifest = Get-Content.*windows/winget/packages\.json'
        $installerScript | Should -Match '\$wingetSources\s*=\s*@\('
        $installerScript | Should -Match 'SourceDetails\.Name -in @\(''winget'', ''msstore''\)'
        $installerScript | Should -Match 'Add-Member -NotePropertyName ciSkipInstall -NotePropertyValue \$true'
        $installerScript | Should -Match '\$null -eq \$skipInstall -or -not \[bool\]\$skipInstall\.Value'
        $installerScript | Should -Match 'Sort-Object -Unique'
        $wingetAssertion | Should -Match 'reported an empty WinGet CI verification inventory'
    }
    It 'should run the real installer in concurrent PowerShell 5.1 and 7 processes' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml') -Raw -Encoding UTF8
        $installerJob = [regex]::Match(
            $workflow,
            '(?ms)^  windows-installer:\s*\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:|\z)'
        ).Groups['job'].Value
        $installerStep = [regex]::Match(
            $installerJob,
            '(?ms)^      - name: Run install\.cmd strict user phase\s*(?<step>.*?)(?=^      - name:|\z)'
        ).Groups['step'].Value
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8

        $installerJob | Should -Match 'fail-fast:\s*false'
        $installerJob | Should -Match 'max-parallel:\s*2'
        $installerJob | Should -Match 'runtime: Windows PowerShell 5\.1[\s\S]*?version: "5\.1"'
        $installerJob | Should -Match 'runtime: PowerShell 7[\s\S]*?version: "7"'
        $installerStep | Should -Match 'shell:\s+cmd'
        $installerStep | Should -Match 'run:\s+powershell\.exe .*Invoke-WindowsInstallerE2E\.ps1'
        $installerJob | Should -Match 'DOTFILES_E2E_POWERSHELL_VERSION:\s+\$\{\{\s*matrix\.version\s*\}\}'

        $installerScript | Should -Match '\$runtimeCommand = if \(\$expectedRuntime -eq ''5\.1''\) \{ ''powershell\.exe'' \} else \{ ''pwsh\.exe'' \}'
        $installerScript | Should -Match 'install\.cmd -NoPause -UserPhaseOnly(?!\s+-WingetVerifyCommandOnly)'
        $installerScript | Should -Match 'RequiredOutputMarkers\s+\$requiredPackageManagerMarkers'
        $installerScript | Should -Match '\[Pnpm\] npm で pnpm をインストールしました'
        $installerScript | Should -Match '\[Npm\] ✓ \$\(\$package\.name\)'
        $installerScript | Should -Match 'if \(\$expectedRuntime -eq ''7''\)'
        $installerScript | Should -Match 'Add-Member -NotePropertyName ciSkipInstall -NotePropertyValue \$true'
        $installerScript | Should -Match '\$powerShellPackages\[0\]\s*\|\s*Add-Member -NotePropertyName ciSkipInstall -NotePropertyValue \$true -Force'
        $installerScript | Should -Match '\$expectedWindowsPackageIds'
        $installerScript | Should -Match 'Assert-WingetInstallSuccess -Output \$out -ExpectedPackageIds \$expectedWindowsPackageIds'
        $installerScript | Should -Match 'Update-ProcessEnvironmentPath -ExcludePath \$runnerPnpmDirectories'
        ([regex]::Matches($installerScript, [regex]::Escape("Invoke-Npm -Arguments @('prefix', '--global')"))).Count | Should -Be 2
        $installerScript | Should -Not -Match '\bnpm prefix --global\b'
        $installerScript | Should -Match 'PowerShell 7 installer E2E unexpectedly used the Windows PowerShell 5\.1 path'
        $installerScript | Should -Match 'Name = ''pnpm''; Arguments = @\(''--version''\)'
        $installerScript | Should -Match 'Write-Host \$failureSummary -ForegroundColor Red'
    }
    It 'should keep the dedicated Windows installer E2E script UTF-8 BOM encoded and parseable' {
        $installerScriptPath = Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1'
        $bytes = [System.IO.File]::ReadAllBytes($installerScriptPath)
        ($bytes[0..2] -join ',') | Should -Be '239,187,191'

        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $installerScriptPath,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
    }

    It 'should verify the installed Codex code-mode host exists beside its shim and launches' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8
        $codexHandler = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/handlers/Handler.Codex.ps1') -Raw

        $installerScript | Should -Match 'codex-code-mode-host\.exe'
        $installerScript | Should -Match 'Get-Command -Name ''codex\.exe'' -CommandType Application'
        $installerScript | Should -Match 'Codex CLI shim is not the command exposed on PATH'
        $installerScript | Should -Match 'code-mode host is missing beside the selected Codex executable'
        $installerScript | Should -Match '\$codexHostPath.*--help'
        $installerScript | Should -Match 'Codex code-mode host --help failed'
        $installerScript | Should -Match '\$codexShimPath.*--help'
        $installerScript | Should -Match 'Codex CLI --help failed'
        $installerScript | Should -Match 'Resolve-CodexPackageExecutablePath'
        $installerScript | Should -Match 'handlers/Handler\.Codex\.ps1'
        $installerScript | Should -Match 'FileAttributes\]::ReparsePoint'
        $codexHandler | Should -Match 'Programs\\Codex'
        $codexHandler | Should -Match 'bin\\codex\.exe'
        $installerScript | Should -Not -Match "PSObject\.Properties\['(LinkType|Target)'\]"
    }
    It 'should resolve Codex package paths in the PS5.1 CI fallback without LinkType or Target metadata' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8
        $codexHandler = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/handlers/Handler.Codex.ps1') -Raw

        $installerScript | Should -Match 'codex-code-mode-host\.exe'
        $installerScript | Should -Match 'Get-Command -Name ''codex\.exe'' -CommandType Application'
        $installerScript | Should -Match 'Codex CLI shim is not the command exposed on PATH'
        $installerScript | Should -Match 'code-mode host is missing beside the selected Codex executable'
        $installerScript | Should -Match '\$codexHostPath.*--help'
        $installerScript | Should -Match 'Codex code-mode host --help failed'
        $installerScript | Should -Match '\$codexShimPath.*--help'
        $installerScript | Should -Match 'Codex CLI --help failed'
        $installerScript | Should -Match 'Resolve-CodexPackageExecutablePath'
        $installerScript | Should -Match 'handlers/Handler\.Codex\.ps1'
        $installerScript | Should -Match 'FileAttributes\]::ReparsePoint'
        $codexHandler | Should -Match 'Programs\\Codex'
        $codexHandler | Should -Match 'bin\\codex\.exe'
        $installerScript | Should -Not -Match "PSObject\.Properties\['(LinkType|Target)'\]"
    }
    It 'should verify ChatGPT Classic is removed by the real Windows installer E2E' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8


        $installerScript | Should -Match '9NT1R1C2HH7J'
        $installerScript.Contains("RETIRED_PACKAGE_CLEANUP: id=9NT1R1C2HH7J status=(removed|absent)") | Should -BeTrue
        $installerScript | Should -Match 'winget list --id 9NT1R1C2HH7J --exact --source msstore'
        $installerScript | Should -Match 'ChatGPT Classic is still installed after cleanup'
    }

    It 'should run the admin-required Visual Studio package through an elevated installer and verify its compiler' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml') -Raw
        $windowsJob = [regex]::Match(
            $workflow,
            '(?ms)^  windows:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value

        $windowsJob | Should -Not -BeNullOrEmpty
        $windowsJob | Should -Match 'WindowsIdentity\]::GetCurrent\(\)'
        $windowsJob | Should -Match 'WindowsPrincipal'
        $windowsJob | Should -Match 'WindowsBuiltinRole\]::Administrator'
        $windowsJob | Should -Match 'runner is not elevated'
        $windowsJob | Should -Match 'name: Bootstrap / Windows \(\$\{\{ matrix\.runtime \}\}\)'
        $windowsJob | Should -Match 'runtime: Windows PowerShell 5\.1\s+executable: powershell\.exe'
        $windowsJob | Should -Match 'runtime: PowerShell 7\s+executable: pwsh\.exe'
        $windowsJob | Should -Match 'WINDOWS_E2E_EXECUTABLE: \$\{\{ matrix\.executable \}\}'
        $windowsJob | Should -Match '& \$env:WINDOWS_E2E_EXECUTABLE'
        $windowsJob | Should -Match 'runtime=\$\{\{ matrix\.runtime \}\}'
        $windowsJob | Should -Match 'scripts/powershell/install\.admin\.ps1'
        $windowsJob | Should -Match '-AdminOnly:\$true'
        $windowsJob | Should -Match 'AutoHotkey\.AutoHotkey'
        $windowsJob | Should -Match 'SkipWslInstall'
        $windowsJob | Should -Match 'SkipVhdExpand'
        $windowsJob | Should -Match 'Microsoft\.VisualStudio\.2022\.BuildTools'
        $windowsJob.Contains('Failure:\s*0') | Should -BeTrue
        $windowsJob | Should -Match 'CI_ADMIN_PACKAGE_SUCCESS: id=Microsoft\.VisualStudio\.2022\.BuildTools'
        $windowsJob.Contains('VC\Tools\MSVC') | Should -BeTrue
        $windowsJob.Contains('bin\Hostx64\x64\cl.exe') | Should -BeTrue
        $windowsJob | Should -Match '\$LASTEXITCODE = 0\s+& \$uiAccess .+--check'
        $windowsJob | Should -Match '\$syntaxExitCode = \$LASTEXITCODE'
        $windowsJob | Should -Match '\$LASTEXITCODE = 0\s+& \$uiAccess .+--self-test'
        $windowsJob | Should -Match '\$selfTestExitCode = \$LASTEXITCODE'
    }

    It 'should run npm pnpm and 1Password executables after the Windows installer' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8


        $installerScript | Should -Match "'agent-browser'"
        $installerScript | Should -Match "Name = 'npm'"
        $installerScript | Should -Match 'agent-browser@0\.38\.1 requires Node\.js >=24\.0\.0'
        $installerScript | Should -Match '\[version\]''24\.0\.0'''
        $installerScript | Should -Match "Name = 'herdr'"
        $installerScript | Should -Match "'pnpm'"
        $installerScript | Should -Match "'gemini'"
        $installerScript | Should -Match "'op\.exe'"
        $installerScript | Should -Match 'Persisted user PATH does not identify an installed AgileBits\.1Password\.CLI package directory'
        $installerScript | Should -Match 'WinGet Links op\.exe shim is missing after OnePasswordCli setup'
        $installerScript | Should -Match "GetEnvironmentVariable\('Path',\s*'User'\)"
        $installerScript | Should -Match "GetEnvironmentVariable\('PNPM_HOME',\s*'User'\)"
        $installerScript | Should -Match 'Get-Command -Name \$requiredCommand\.Name -CommandType Application'
        $installerScript | Should -Match 'Windows installer did not expose required command'
        $installerScript | Should -Match 'Windows installer command.*failed'
    }

    It 'should diagnose an unsupported Node version before probing agent-browser' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8


        $nodePreflightIndex = $installerScript.IndexOf('$nodeVersionOutput = @(node --version 2>&1)', [System.StringComparison]::Ordinal)
        $requiredCommandIndex = $installerScript.IndexOf('$requiredCommands = @(', [System.StringComparison]::Ordinal)

        $nodePreflightIndex | Should -BeGreaterThan -1
        $requiredCommandIndex | Should -BeGreaterThan $nodePreflightIndex
    }

    It 'should derive the Windows E2E inventory when optional package metadata is omitted' {
        $installerScript = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1') -Raw -Encoding UTF8
        $predicateMatch = [regex]::Match(
            $installerScript,
            '(?ms)\$expectedWindowsPackageIds\s*=\s*@\(\s*\$wingetSources\s*\|\s*ForEach-Object\s*\{\s*\$_.Packages\s*\}\s*\|\s*Where-Object\s*\{(.*?)\}\s*\|'
        )
        $predicateMatch.Success | Should -BeTrue

        Set-StrictMode -Version Latest
        $predicate = [scriptblock]::Create($predicateMatch.Groups[1].Value)
        $packages = @(
            [pscustomobject]@{ PackageIdentifier = 'Ordinary.Package' }
            [pscustomobject]@{ PackageIdentifier = 'CiSkipped.Package'; ciSkipInstall = $true }
            [pscustomobject]@{ PackageIdentifier = 'Admin.Package'; requiresAdmin = $true }
            [pscustomobject]@{ PackageIdentifier = 'Feature.Package'; installFeature = 'optional-feature' }
            [pscustomobject]@{ PackageIdentifier = 'ManualSkip.Package'; skipInstall = $true }
            [pscustomobject]@{ PackageIdentifier = 'EmptyFeature.Package'; installFeature = '' }
        )
        $actualIds = @($packages | Where-Object $predicate | ForEach-Object { [string]$_.PackageIdentifier } | Sort-Object -Unique)

        $actualIds | Should -Be @('CiSkipped.Package', 'EmptyFeature.Package', 'Ordinary.Package')
    }
    It 'should build the NixOS WSL system on hosted Nix CI' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $nixWorkflow | Should -Match 'Build NixOS WSL system'
        $nixWorkflow | Should -Match 'nix build \.#nixosConfigurations\.nixos\.config\.system\.build\.toplevel --no-link'
    }

    It 'should configure the llm-agents binary cache for Codex system builds' {
        $flake = Get-Content -LiteralPath (Join-Path $script:repoRoot "flake.nix") -Raw
        $postInstall = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/nixos-wsl-postinstall.sh") -Raw
        $hostModule = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/modules/host/default.nix") -Raw
        $bootstrapWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $flake | Should -Match 'extra-substituters\s*=\s*\[\s*"https://cache\.numtide\.com"'
        $flake | Should -Match 'extra-trusted-public-keys\s*=\s*\[\s*"niks3\.numtide\.com-1:'
        $postInstall | Should -Match 'extra-substituters = https://cache\.numtide\.com'
        $postInstall | Should -Match 'extra-trusted-public-keys = niks3\.numtide\.com-1:'
        $hostModule | Should -Match 'extra-substituters\s*=\s*\[\s*"https://cache\.numtide\.com"'
        $hostModule | Should -Match 'extra-trusted-public-keys\s*=\s*\[\s*"niks3\.numtide\.com-1:'
        $bootstrapWorkflow | Should -Match 'Build macOS declarative output[\s\S]*?nix build \.#darwinConfigurations\.macos\.system --impure --no-link[\s\S]*?--option extra-substituters "\$NUMTIDE_CACHE"'
        $bootstrapWorkflow | Should -Match 'NUMTIDE_CACHE_KEY:\s*niks3\.numtide\.com-1:'
        $bootstrapWorkflow | Should -Match 'nix-test:[\s\S]*?NIX_CONFIG:\s*\|[\s\S]*?extra-substituters = https://cache\.numtide\.com[\s\S]*?extra-trusted-public-keys = niks3\.numtide\.com-1:'
        $bootstrapWorkflow | Should -Match 'linux-build:[\s\S]*?NIX_CONFIG:\s*\|[\s\S]*?extra-substituters = https://cache\.numtide\.com[\s\S]*?extra-trusted-public-keys = niks3\.numtide\.com-1:'
    }

    It 'should build the font package set on hosted Nix CI' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $nixWorkflow | Should -Match 'nix build \.#fonts'
    }

    It 'keeps formatting and semantic Nix tests as independent gates' {
        $bootstrapWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $bootstrapWorkflow | Should -Match 'nix-format:[\s\S]*?Check source formatting \(style only\)[\s\S]*?nix fmt -- --fail-on-change'
        $bootstrapWorkflow | Should -Match 'nix-test:[\s\S]*?needs: \[changes, nix-lint\]'
        $bootstrapWorkflow | Should -Not -Match 'nix-test:[\s\S]*?needs: \[changes, nix-lint, nix-format\]'
        $bootstrapWorkflow | Should -Match 'Formatting is an independent style gate'
    }

    It 'should free hosted runner disk space before Nix package builds' {
        $nixWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

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
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml"
        $scriptPath = Join-Path $script:repoRoot "scripts/powershell/ci/Invoke-NixosWslE2E.ps1"
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $script = Get-Content -LiteralPath $scriptPath -Raw
        $wslJob = [regex]::Match($workflow, '(?s)(?m)^  wsl:.*?(?=^  [\w-]+:|\z)').Value
        $jobTimeout = [int]([regex]::Match($wslJob, '(?m)^    timeout-minutes:\s+(\d+)\s*$').Groups[1].Value)
        $rebuildTimeoutSeconds = [int]([regex]::Match($script, '(?m)^\s*\[int\]\$PostInstallTimeoutSeconds\s*=\s*(\d+)(?=\s*[,\r\n])').Groups[1].Value)
        $rebuildBudgetCount = [regex]::Matches($script, '\$context\.Options\["PostInstallTimeoutSeconds"\]\s*=\s*\$PostInstallTimeoutSeconds|\$rebuildContext\.Options\["NixRebuildTimeoutSeconds"\]\s*=\s*\$PostInstallTimeoutSeconds').Count

        $workflow | Should -Match 'runs-on:\s+windows-2025'
        $jobTimeout | Should -BeGreaterOrEqual (($rebuildTimeoutSeconds * $rebuildBudgetCount / 60) + 60) -Because 'the job must allow each independent rebuild timeout plus one hour for WSL setup and verification'
        $rebuildBudgetCount | Should -Be 2 -Because 'the E2E performs a post-install switch and a separate Hermes-enabled switch'
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
        $script | Should -Match 'SkipFlakeUpdate"\] = \$true'
        $script | Should -Match 'handlers\\Handler\.NixOSWSL\.ps1'
        $script | Should -Match '\$handler = \[NixOSWSLHandler\]::new\(\)'
        $script | Should -Match '\$result = \$handler\.Apply\(\$context\)'
        $script | Should -Match 'CI_ASSERTION: production NixOSWSLHandler and nixos-rebuild switch completed'
        $script | Should -Match 'NIX_CONFIG is missing the GitHub access-token configuration inside WSL'
        $script | Should -Match 'access-tokens = github\.com='
        $script | Should -Not -Match 'Write-Host\s+\$env:NIX_CONFIG|printenv\s+NIX_CONFIG'
        $script | Should -Match 'Welcome to your new NixOS-WSL system'
        $script | Should -Match 'nixos-rebuild list-generations'
        $script | Should -Match 'handlers\\Handler\.NixRebuild\.ps1'
        $script | Should -Match '\$rebuildContext\.Options\["WithHermes"\] = \$true'
        $script | Should -Match '\$rebuildContext\.Options\["SkipFlakeUpdate"\] = \$true'
        $script | Should -Match '\$rebuildContext\.Options\["NixRebuildTimeoutSeconds"\] = \$PostInstallTimeoutSeconds'
        $script | Should -Match '\[int\]\$PostInstallTimeoutSeconds = 7200'
        $script | Should -Match '\$rebuildHandler = \[NixRebuildHandler\]::new\(\)'
        $script | Should -Match 'function Write-WslRebuildDiagnostic'
        $script | Should -Match 'Write-WslRebuildDiagnostic -Phase "before Hermes rebuild"'
        $script | Should -Match 'Write-WslRebuildDiagnostic -Phase "after Hermes rebuild failure"'
        $script | Should -Match 'free -h'
        $script | Should -Match 'df -h / /nix'
        $script | Should -Match 'dmesg --time-format iso'
        $script | Should -Match '\$diagnosticScript = \$diagnosticScript -replace "`r`n\?", "`n"'
        $script | Should -Match '\$rebuildHandler\.Apply\(\$rebuildContext\)'
        $script | Should -Match 'CI_ASSERTION: production NixRebuildHandler applied WithHermes'
        $script | Should -Match 'hermes_executable="\$\(readlink -f "\$\(command -v hermes\)"\)"'
        $script | Should -Match '/nix/store/\*'
        $script | Should -Match 'hermes --version'
        $script | Should -Match 'OPENROUTER_API_KEY=ci'
        $script | Should -Match 'API_SERVER_ENABLED=true'
        $script | Should -Match 'API_SERVER_PORT=18642'
        $script | Should -Match 'http://127\.0\.0\.1:18642/health/detailed'
        $script | Should -Match 'nix shell --inputs-from /home/nixos/\.dotfiles nixpkgs#curl nixpkgs#jq --command bash -s <<''DOTFILES_HERMES_READINESS'''
        $script | Should -Match 'Authorization: Bearer dotfiles-ci-health-probe'
        $script | Should -Match 'Authorization: Bearer invalid-dotfiles-ci-health-probe'
        $script | Should -Match 'expect_unauthorized ''missing bearer token'''
        $script | Should -Match 'expect_unauthorized ''invalid bearer token'''
        $script | Should -Match 'set -euo pipefail'
        $script | Should -Match 'status_code != 000'
        $script | Should -Match 'for attempt in \{1\.\.__READINESS_ATTEMPTS__\}'
        $script | Should -Match 'Hermes \$description probe expected HTTP 401 but received \$status_code'
        $script | Should -Match '\$script:InvokeWslOriginal = \(Get-Command Invoke-Wsl\)\.ScriptBlock'
        $script | Should -Match '\$TimeoutSeconds = 900'
        $script | Should -Match 'jq -e'
        $script | Should -Match '\.status == "ok"'
        $script | Should -Match '\.readiness\.status == "ok"'
        $script | Should -Match '\.readiness\.checks \| type == "object" and length > 0 and all\(\.\[\]; \.status == "ok"\)'
        $script | Should -Match '\["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"\]'
        $script | Should -Match '\$readinessAttempts\s*=\s*30'
        $script | Should -Match '\$readinessCurlTimeoutSeconds\s*=\s*2'
        $script | Should -Match '\$readinessRetryDelaySeconds\s*=\s*1'
        $script | Should -Match '\$readinessTimeoutMarginSeconds\s*=\s*30'
        $script | Should -Match '\$readinessTimeoutSeconds\s*=\s*\(\$readinessAttempts \* \(\$readinessCurlTimeoutSeconds \+ \$readinessRetryDelaySeconds\)\) \+ \$readinessTimeoutMarginSeconds'
        $script | Should -Match '\.Replace\(''__READINESS_ATTEMPTS__'', \[string\]\$readinessAttempts\)'
        $script | Should -Match '\.Replace\(''__READINESS_CURL_TIMEOUT_SECONDS__'', \[string\]\$readinessCurlTimeoutSeconds\)'
        $script | Should -Match '\.Replace\(''__READINESS_RETRY_DELAY_SECONDS__'', \[string\]\$readinessRetryDelaySeconds\)'
        $script | Should -Match '-TimeoutSeconds \$readinessTimeoutSeconds'
        $script | Should -Match 'chmod 600 /home/nixos/\.hermes/\.env'
        $script | Should -Match 'preserve-existing-hermes-state'
        $script | Should -Match 'stat -c .*\.hermes/\.env'
        $script | Should -Not -Match 'systemctl --user set-environment OPENROUTER_API_KEY=ci'
        $script | Should -Not -Match 'systemctl --user restart hermes-agent\.service'
        $script | Should -Match 'systemctl --user is-active hermes-agent\.service'
        $script | Should -Match 'systemctl --user is-enabled hermes-agent\.service'
        $script | Should -Match 'loginctl show-user nixos -p Linger --value \| grep -qx yes'
        $script | Should -Not -Match 'systemctl --user restart hermes-agent\.service'
        $workflow | Should -Match 'GITHUB_TOKEN:\s+\$\{\{ secrets\.GITHUB_TOKEN \}\}'
        $workflow | Should -Match 'NIX_CONFIG:\s*\|\s*access-tokens = github\.com=\$\{\{ secrets\.GITHUB_TOKEN \}\}'
        $workflow | Should -Match 'WSLENV:\s+GITHUB_TOKEN/u:NIX_CONFIG/u'
        $script | Should -Match ([regex]::Escape('GH_TOKEN=ci TAVILY_API_KEY=ci GITHUB_WORK_TOKEN=ci zsh -ic "type z >/dev/null && bindkey"'))
        $script | Should -Match ([regex]::Escape('rg "\"\^\[q\" __zoxide_zi_widget"'))
        $script | Should -Not -Match ([regex]::Escape('rg "\"\^\[z\" __zoxide_zi_widget"'))
        $script | Should -Match 'Remove-TemporaryDistro'
    }

    It 'should wait for the Hermes listener before checking both unauthorized responses' {
        $scriptPath = Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-NixosWslE2E.ps1'
        $script = Get-Content -LiteralPath $scriptPath -Raw
        $shellMatch = [regex]::Match($script, '(?ms)^[ \t]*\$readinessCommand = @''\r?\n(?<body>.*?)^[ \t]*''@')
        $shellMatch.Success | Should -BeTrue

        $shell = $shellMatch.Groups['body'].Value
        $shell = $shell -replace "(?m)^nix shell .*?<<'DOTFILES_HERMES_READINESS'\r?\n", ''
        $shell = $shell -replace "(?m)^DOTFILES_HERMES_READINESS\r?\n$", ''
        $shell = $shell.Replace('__READINESS_ATTEMPTS__', '3')
        $shell = $shell.Replace('__READINESS_CURL_TIMEOUT_SECONDS__', '1')
        $shell = $shell.Replace('__READINESS_RETRY_DELAY_SECONDS__', '0')

        $bash = 'C:\Program Files\Git\bin\bash.exe'
        if (-not (Test-Path -LiteralPath $bash)) {
            $bashCommand = Get-Command bash.exe -ErrorAction Stop
            $bash = $bashCommand.Source
        }
        $bash | Should -Exist

        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-readiness-" + [guid]::NewGuid().ToString('N'))
        $previousProbeState = $env:HERMES_PROBE_STATE
        $previousProbeScenario = $env:HERMES_PROBE_SCENARIO
        $previousMissingCheck = $env:HERMES_MISSING_CHECK
        $null = New-Item -ItemType Directory -Path $temp
        try {
            # The readiness script itself is the subject; curl/jq are external
            # process boundaries, so supply deterministic HTTP/JSON responses.
            $curlStub = @'
jq() {
  local query="$2"
  local response
  response=$(cat)
  node -e 'const [query, raw] = process.argv.slice(1); const data = JSON.parse(raw); const required = ["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"]; const completeQuery = required.every((name) => query.includes(name)); const checks = data.readiness && data.readiness.checks; const healthy = completeQuery && data.status === "ok" && data.readiness.status === "ok" && checks && typeof checks === "object" && Object.keys(checks).length > 0 && Object.values(checks).every((check) => check && check.status === "ok") && required.every((name) => checks[name] && checks[name].status === "ok"); process.exitCode = healthy ? 0 : 1' "$query" "$response"
}
curl() {
local scenario=${HERMES_PROBE_SCENARIO:?}
local state_dir=${HERMES_PROBE_STATE:?}
local auth=missing
local arg
for arg in "$@"; do
  case "$arg" in
    'Authorization: Bearer invalid-dotfiles-ci-health-probe') auth=invalid ;;
    'Authorization: Bearer dotfiles-ci-health-probe') auth=valid ;;
  esac
done
if [[ $auth != valid ]]; then
  if [[ $scenario == wrong-auth-response ]]; then
    printf '200'
    return 0
  fi
  count_file="$state_dir/$auth"
  count=0
  [[ -f $count_file ]] && read -r count < "$count_file"
  count=$((count + 1))
  printf '%s\n' "$count" > "$count_file"
  if [[ $scenario == startup && $count == 1 ]]; then
    return 7
  fi
  printf '401'
  return 0
fi
case "$scenario" in
  healthy|startup)
    printf '%s' '{"status":"ok","readiness":{"status":"ok","checks":{"state_db":{"status":"ok"},"session_store":{"status":"ok"},"config":{"status":"ok"},"model":{"status":"ok"},"disk":{"status":"ok"},"gateway":{"status":"ok"},"background_queues":{"status":"ok"}}}}'
    ;;
  unhealthy)
    printf '%s' '{"status":"ok","readiness":{"status":"error","checks":{"state_db":{"status":"ok"},"session_store":{"status":"ok"},"config":{"status":"ok"},"model":{"status":"error"},"disk":{"status":"ok"},"gateway":{"status":"ok"},"background_queues":{"status":"ok"}}}}'
    ;;
    missing-required-check)
      printf '%s' '{"status":"ok","readiness":{"status":"ok","checks":{"state_db":{"status":"ok"},"session_store":{"status":"ok"},"config":{"status":"ok"},"model":{"status":"ok"},"disk":{"status":"ok"},"gateway":{"status":"ok"},"background_queues":{"status":"ok"}}}}' |
        node -e 'let raw = ""; process.stdin.on("data", (chunk) => raw += chunk); process.stdin.on("end", () => { const data = JSON.parse(raw); delete data.readiness.checks[process.argv[1]]; process.stdout.write(JSON.stringify(data)); });' "$HERMES_MISSING_CHECK"
    ;;
esac
}
'@
            $shellPath = Join-Path $temp 'readiness.sh'
            $shell = $curlStub + "`n" + $shell
            [System.IO.File]::WriteAllText($shellPath, $shell.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
            $env:HERMES_PROBE_STATE = $temp

            function Invoke-ReadinessProbe {
                param([Parameter(Mandatory)][string]$BashPath, [Parameter(Mandatory)][string]$ScriptPath)
                $previousPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $probeOutput = @(& $BashPath $ScriptPath 2>&1)
                    $probeExitCode = $LASTEXITCODE
                }
                finally {
                    $ErrorActionPreference = $previousPreference
                }
                [PSCustomObject]@{ Output = $probeOutput; ExitCode = $probeExitCode }
            }

            foreach ($scenario in @('startup', 'healthy')) {
                Remove-Item -LiteralPath (Join-Path $temp 'missing'), (Join-Path $temp 'invalid') -Force -ErrorAction SilentlyContinue
                $env:HERMES_PROBE_SCENARIO = $scenario
                $probe = Invoke-ReadinessProbe -BashPath $bash -ScriptPath $shellPath
                $output = $probe.Output
                $exitCode = $probe.ExitCode
                $exitCode | Should -Be 0 -Because "$scenario must eventually receive strict 401 responses and a healthy authenticated readiness response; output: $($output -join ' | ')"
                $expectedProbeCount = if ($scenario -eq 'startup') { '2' } else { '1' }
                (Get-Content -LiteralPath (Join-Path $temp 'missing') -Raw).Trim() | Should -Be $expectedProbeCount
                (Get-Content -LiteralPath (Join-Path $temp 'invalid') -Raw).Trim() | Should -Be $expectedProbeCount
            }

            $env:HERMES_PROBE_SCENARIO = 'unhealthy'
            $probe = Invoke-ReadinessProbe -BashPath $bash -ScriptPath $shellPath
            $output = $probe.Output
            $exitCode = $probe.ExitCode
            $exitCode | Should -Not -Be 0 -Because 'an unhealthy Hermes check must fail the readiness contract'
            ($output -join "`n") | Should -Match 'Hermes readiness did not report all required checks healthy'

            $env:HERMES_PROBE_SCENARIO = 'wrong-auth-response'
            $probe = Invoke-ReadinessProbe -BashPath $bash -ScriptPath $shellPath
            $output = $probe.Output
            $exitCode = $probe.ExitCode
            $exitCode | Should -Not -Be 0 -Because 'an HTTP response other than 401 must not be treated as listener startup'
            ($output -join "`n") | Should -Match 'missing bearer token probe expected HTTP 401 but received 200'

            foreach ($requiredCheck in @('state_db', 'session_store', 'config', 'model', 'disk', 'gateway', 'background_queues')) {
                Remove-Item -LiteralPath (Join-Path $temp 'missing'), (Join-Path $temp 'invalid') -Force -ErrorAction SilentlyContinue
                $env:HERMES_PROBE_SCENARIO = 'missing-required-check'
                $env:HERMES_MISSING_CHECK = $requiredCheck
                $probe = Invoke-ReadinessProbe -BashPath $bash -ScriptPath $shellPath
                $output = $probe.Output
                $exitCode = $probe.ExitCode
                $exitCode | Should -Not -Be 0 -Because "missing required readiness check $requiredCheck must fail the contract"
                ($output -join "`n") | Should -Match 'Hermes readiness did not report all required checks healthy'
            }
        }
        finally {
            if ($null -eq $previousProbeState) { Remove-Item Env:HERMES_PROBE_STATE -ErrorAction SilentlyContinue } else { $env:HERMES_PROBE_STATE = $previousProbeState }
            if ($null -eq $previousProbeScenario) { Remove-Item Env:HERMES_PROBE_SCENARIO -ErrorAction SilentlyContinue } else { $env:HERMES_PROBE_SCENARIO = $previousProbeScenario }
            if ($null -eq $previousMissingCheck) { Remove-Item Env:HERMES_MISSING_CHECK -ErrorAction SilentlyContinue } else { $env:HERMES_MISSING_CHECK = $previousMissingCheck }
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'should bound legacy WSL setup calls and both cleanup commands' {
        $scriptPath = Join-Path $script:repoRoot 'scripts/powershell/ci/Invoke-NixosWslE2E.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $invokeWslAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Wsl'
            }, $true)
        $cleanupAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-TemporaryDistro'
            }, $true)
        $invokeWslAst | Should -Not -BeNullOrEmpty
        $cleanupAst | Should -Not -BeNullOrEmpty

        $script:observedTimeout = $null
        $script:observedArguments = @()
        $script:InvokeWslOriginal = {
            param([string[]]$Arguments, [int]$TimeoutSeconds)
            $script:observedTimeout = $TimeoutSeconds
            $script:observedArguments = $Arguments
            $global:LASTEXITCODE = 0
            'bounded-call'
        }
        . ([scriptblock]::Create($invokeWslAst.Extent.Text))

        Invoke-Wsl -Arguments @('--status') | Should -Be 'bounded-call'
        $script:observedTimeout | Should -Be 900
        $script:observedArguments | Should -Be @('--status')
        Invoke-Wsl -Arguments @('--status') -TimeoutSeconds 0 | Should -Be 'bounded-call'
        $script:observedTimeout | Should -Be 900
        Invoke-Wsl -Arguments @('--status') -TimeoutSeconds 45 | Should -Be 'bounded-call'
        $script:observedTimeout | Should -Be 45

        $script:cleanupCalls = @()
        function Invoke-WslChecked {
            param([string[]]$Arguments, [int]$TimeoutSeconds, [switch]$AllowFailure)
            $script:cleanupCalls += [pscustomobject]@{
                Arguments      = $Arguments
                TimeoutSeconds = $TimeoutSeconds
                AllowFailure   = [bool]$AllowFailure
            }
        }
        . ([scriptblock]::Create($cleanupAst.Extent.Text))
        Remove-TemporaryDistro -Name 'NixOS-CI-Test'

        $script:cleanupCalls.Count | Should -Be 2
        $script:cleanupCalls[0].Arguments | Should -Be @('--terminate', 'NixOS-CI-Test')
        $script:cleanupCalls[0].TimeoutSeconds | Should -Be 60
        $script:cleanupCalls[0].AllowFailure | Should -BeTrue
        $script:cleanupCalls[1].Arguments | Should -Be @('--unregister', 'NixOS-CI-Test')
        $script:cleanupCalls[1].TimeoutSeconds | Should -Be 300
        $script:cleanupCalls[1].AllowFailure | Should -BeTrue
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

    It 'should run the complete PowerShell test suite in parallel on Windows PowerShell 5.1 and PowerShell 7' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-powershell.yml') -Raw
        $testJob = [regex]::Match(
            $workflow,
            '(?ms)^  test:\s*\r?\n(?<job>.*?)(?=^  [a-zA-Z0-9_-]+:|\z)'
        ).Groups['job'].Value

        $testJob | Should -Match 'fail-fast:\s*false'
        $testJob | Should -Match 'max-parallel:\s*2'
        $testJob | Should -Match 'runtime: Windows PowerShell 5\.1\s+executable: powershell\.exe\s+module_directory: WindowsPowerShell'
        $testJob | Should -Match 'runtime: PowerShell 7\s+executable: pwsh\.exe\s+module_directory: PowerShell'
        $testJob | Should -Match 'name: Test \(Pester \+ Codecov / \$\{\{ matrix\.runtime \}\}\)'
        $testJob | Should -Match 'name: test-results-\$\{\{ matrix\.runtime \}\}'
        $testJob | Should -Not -Match 'shell:\s+\$\{\{\s*matrix\.'
        $testJob | Should -Match 'PS_TEST_EXECUTABLE: \$\{\{ matrix\.executable \}\}'
        $testJob | Should -Match '& \$env:PS_TEST_EXECUTABLE -NoProfile -File'
        $testJob | Should -Match 'Documents\\\$env:PS_MODULE_DIRECTORY\\Modules'
        $testJob | Should -Match 'WindowsPowerShell\\Modules'
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
        $powershellWorkflow | Should -Match 'Copy-Item -LiteralPath \.\\scripts\\powershell\\install\.ps1'
        $powershellWorkflow | Should -Not -Match 'STUB_INSTALL_COMPLETE'
        $powershellWorkflow | Should -Match 'User Phase Complete!'
    }

    It 'should retry winget source update when the runner reports Cancelled' {
        $wingetWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $wingetWorkflow | Should -Match 'function Invoke-WingetSourceUpdate'
        $wingetWorkflow | Should -Match '\bCancelled\b'
        $wingetWorkflow | Should -Match 'winget source reset --force'
        $wingetWorkflow | Should -Match 'throw "winget source update did not complete after \$Attempts attempts"'
    }

    It 'should expose package provider report build logs in CI' {
        $bootstrapWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw
        $consistencyWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-consistency.yml") -Raw

        $bootstrapWorkflow | Should -Match 'nix build \.#package-support-report --no-link --print-build-logs'
        $bootstrapWorkflow | Should -Match 'nix build \.#package-support-report --no-link --print-out-paths --print-build-logs'
        $consistencyWorkflow | Should -Match 'nix build \.#package-support-report --print-build-logs'
        $consistencyWorkflow | Should -Not -Match 'nix build \.#package-support-report[^\r\n]*2>/dev/null'
    }

    It 'should pin the WinGet fallback module and avoid an AllUsers repair' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-bootstrap.yml") -Raw

        $workflow | Should -Match "Install-Module -Name Microsoft\.WinGet\.Client -RequiredVersion '1\.29\.280' -Scope CurrentUser -Force -Repository PSGallery"
        $workflow | Should -Match 'Repair-WinGetPackageManager'
        $workflow | Should -Not -Match 'Repair-WinGetPackageManager -AllUsers'
    }

    It 'should verify generated npm package catalog consistency' {
        $consistencyWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-consistency.yml") -Raw

        (Get-CiJobPattern -Output 'package_catalog') | Should -Contain 'windows/npm/packages.json'
        $consistencyWorkflow | Should -Match '/tmp/winget-export/npm/packages\.json'
        $consistencyWorkflow | Should -Match 'windows/npm/packages\.json'
    }

    It 'should trigger entrypoint tests when install.cmd or bootstrap tests change' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $powershellWorkflow | Should -Match 'needs.changes.outputs.powershell_test'
        (Get-CiJobPattern -Output 'powershell_test') | Should -Contain '**/*.cmd'
        (Get-CiJobPattern -Output 'powershell_test') | Should -Contain 'docker/**'
    }

    It 'should assign every Bats file to exactly one CI owner' {
        $contractWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-contract.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw
        $devcontainerBatsScript = Get-Content -LiteralPath (Join-Path $script:repoRoot ".devcontainer/ci/bats.sh") -Raw
        $devcontainerPaths = Get-CiJobPattern -Output 'devcontainer'
        $devcontainerWorkflow | Should -Match 'needs.changes.outputs.devcontainer'

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
                $devcontainerPaths | Should -Contain "tests/bash/$batsFile"
            }
            else {
                $contractWorkflow | Should -Match 'bats_files=\(tests/bash/\*\.bats\)'
            }
        }

        $excludedBats.Count | Should -Be 2
        $devcontainerPaths | Should -Contain 'tests/bash/install_macos.bats'
        $devcontainerPaths | Should -Contain 'tests/bash/install_linux.bats'
        $devcontainerPaths | Should -Not -Contain 'tests/bash/**'

        $activeBatsInvocations = @(
            $devcontainerBatsScript -split '\r?\n' |
                Where-Object { $_ -match '^\s*--command bats\s+' }
        )
        $activeBatsInvocations.Count | Should -Be 1
        $activeBatsInvocations[0].Trim() | Should -Be '--command bats --print-output-on-failure "${owned_bats_files[@]}"'
        $ownedArray = [regex]::Match($devcontainerBatsScript, '(?ms)^owned_bats_files=\((.*?)^\)')
        $ownedArray.Success | Should -BeTrue
        $declaredPaths = @($ownedArray.Groups[1].Value.Trim() -split '\s+')
        $declaredPaths.Count | Should -Be 2
        $declaredPaths | Should -Contain 'tests/bash/install_linux.bats'
        $declaredPaths | Should -Contain 'tests/bash/install_macos.bats'
    }

    It 'should trigger PowerShell CI when Plane GitHub sync config changes' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $powershellWorkflow | Should -Match 'needs.changes.outputs.powershell_test'
        (Get-CiJobPattern -Output 'powershell_test') | Should -Contain 'chezmoi/**'
    }

    It 'should trigger dcnvim platform tests when dcnvim implementations change' {
        $chezmoiWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-chezmoi.yml") -Raw
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        (Get-CiJobPattern -Output 'chezmoi_lint') | Should -Contain 'chezmoi/**'
        $chezmoiWorkflow | Should -Match '\.\\tests\\Invoke-Tests\.ps1 -Path \.\\tests\\chezmoi'
        $powershellWorkflow | Should -Match 'needs.changes.outputs.powershell_test'
        (Get-CiJobPattern -Output 'powershell_test') | Should -Contain '**/*.ps1'
        $devcontainerWorkflow | Should -Match 'needs.changes.outputs.devcontainer'
        (Get-CiJobPattern -Output 'devcontainer') | Should -Contain 'scripts/sh/dcnvim.sh'
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

    It 'should preserve the Linux bootstrap acceptance coverage in the unified workflow' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml') -Raw

        $workflow | Should -Match 'Bootstrap / Linux / E2E / Ubuntu'
        $workflow | Should -Match 'Bootstrap / Linux / E2E / Debian'
        $workflow | Should -Match 'Bootstrap / Linux / E2E / NixOS'
        $workflow | Should -Match 'systemd-nspawn'
        $workflow | Should -Match '(?s)for _ in \$\(seq 1 60\).*machinectl shell.*systemctl is-system-running'
        $workflow | Should -Match 'dotfiles_run_in_group docker.*verify-environment\.sh --runtime'
        $workflow | Should -Match 'bootstrap-nixos-vm'
        $workflow | Should -Match '\./\.github/e2e/run-bootstrap-acceptance\.sh'
        $workflow | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
    }

    It 'should run WSL E2E for fork pull requests and require it in the unified workflow' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml') -Raw
        $test = Get-Content -LiteralPath (Join-Path $script:repoRoot 'nix/tests/bootstrap-nixos.nix') -Raw

        $wslJob = [regex]::Match(
            $workflow,
            '(?ms)^  wsl:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $wslJob | Should -Match "(?m)^\s+if:\s+\$\{\{ needs\.changes\.outputs\.wsl == 'true' \}\}$"
        $wslJob | Should -Match 'persist-credentials:\s+false'
        $wslJob | Should -Not -Match 'pull_request\.head\.repo\.full_name'
        $wslJob | Should -Match 'HEAD_REF:\s+\$\{\{ github\.head_ref \}\}'
        $wslJob | Should -Match 'REF_NAME:\s+\$\{\{ github\.ref_name \}\}'
        $wslJob | Should -Match 'Invoke-NixosWslE2E\.ps1'

        $completeJob = [regex]::Match(
            $workflow,
            '(?ms)^  complete:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value
        $completeJob | Should -Match "(?m)^\s+WSL_REQUIRED:\s+\$\{\{ needs\.changes\.outputs\.wsl \}\}$"
        $test | Should -Match 'DOTFILES_NIXOS_PREBUILT_SYSTEM=\$\{nodes\.machine\.system\.build\.toplevel\}'
        $test | Should -Match 'system\.switch\.enable\s*=\s*true'
        $test | Should -Match 'docker/hermes-service/compose\.yml'
    }

    It 'should keep hosted Windows and Darwin contracts in the unified workflow' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml') -Raw

        $workflow | Should -Match 'runs-on:\s+windows-2025'
        $workflow | Should -Match 'runs-on:\s+macos-15'
        $workflow | Should -Match "Install-Module -Name Pester -RequiredVersion '5\.6\.1'"
        $workflow | Should -Match '(?s)Invoke-Tests\.ps1.*?-MinimumCoverage 0'
        $workflow | Should -Match 'brew install bash coreutils go-task lua'
        $workflow | Should -Match 'nix build \.\#darwinConfigurations\.macos\.system --impure --no-link'
        $workflow | Should -Match 'runtime=not-applicable-on-github-hosted-runner'
        $workflow | Should -Not -Match 'runs-on:\s*\[?self-hosted'
    }

    It 'should run Hammerspoon syntax and behavioral contracts in the required macOS job' {
        $workflowPath = Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $macosJob = [regex]::Match(
            $workflow,
            '(?ms)^  darwin:\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)'
        ).Value

        $macosJob | Should -Not -BeNullOrEmpty
        $macosJob | Should -Match 'brew install bash coreutils go-task lua'
        $macosJob | Should -Not -Match 'bash scripts/sh/.*wezterm.*nightly'
        $macosJob | Should -Match 'command -v lua'
        $macosJob | Should -Match 'command -v luac'
        $macosJob | Should -Match 'env -u DOTFILES_SKIP_FLAKE_UPDATE -u DOTFILES_USER'
        $macosJob | Should -Match 'luac -p chezmoi/terminals/hammerspoon/init\.lua'
        $macosJob | Should -Match 'lua tests/lua/hammerspoon_terminal_prefix_test\.lua'
        $macosJob | Should -Not -Match 'continue-on-error:\s*true'
        $macosJob | Should -Not -Match '(?:command -v (?:lua|luac).*(?:\|\| true)|if\s+command -v (?:lua|luac))'
        $macosJob.IndexOf('brew install bash bats-core coreutils go-task lua') |
            Should -BeLessThan $macosJob.IndexOf('luac -p chezmoi/terminals/hammerspoon/init.lua')
    }

    It 'should install chezmoi before every Windows job that runs chezmoi template tests' {
        $workflowCases = @(
            @{ Path = '.github/workflows/ci-chezmoi.yml'; Job = 'lint'; TestMarker = '.\tests\Invoke-Tests.ps1' },
            @{ Path = '.github/workflows/ci-powershell.yml'; Job = 'test'; TestMarker = 'Invoke-Tests.ps1' },
            @{ Path = '.github/workflows/ci-bootstrap.yml'; Job = 'windows'; TestMarker = 'Invoke-Tests.ps1' }
        )

        foreach ($case in $workflowCases) {
            $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot $case.Path) -Raw
            $job = [regex]::Match(
                $workflow,
                "(?ms)^  $($case.Job):\s*.*?(?=^  [a-zA-Z0-9_-]+:\s*$|\z)"
            ).Value

            $job | Should -Not -BeNullOrEmpty
            $job | Should -Match 'uses: \.\/\.github\/actions\/install-chezmoi'
            $job.IndexOf('uses: ./.github/actions/install-chezmoi') |
                Should -BeLessThan $job.IndexOf($case.TestMarker)
        }
    }

    It 'should keep the shared chezmoi installer independent of WinGet' {
        $action = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/actions/install-chezmoi/action.yml') -Raw

        $action | Should -Match 'https://get\.chezmoi\.io/ps1'
        $action | Should -Match '-BinDir \$binDir -Tag latest'
        $action | Should -Not -Match 'winget install.*chezmoi'
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

    It 'should expose one platform-routed Bootstrap CI workflow' {
        $workflowPath = Join-Path $script:repoRoot '.github/workflows/ci-bootstrap.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should -Match 'name:\s+Bootstrap CI'
        $workflow | Should -Match 'manifest:\s+ci/bootstrap-path-routing\.json'
        $workflow | Should -Match 'Bootstrap / Linux / Build'
        $workflow | Should -Match 'Bootstrap / Darwin'
        $workflow | Should -Match 'Bootstrap / WSL'
        $workflow | Should -Match 'Bootstrap / Windows'
        $workflow | Should -Match 'Bootstrap / Complete'
        $workflow | Should -Match "needs\.changes\.outputs\.linux == 'true'"
        $workflow | Should -Match "needs\.changes\.outputs\.darwin == 'true'"
        $workflow | Should -Match "needs\.changes\.outputs\.wsl == 'true'"
        $workflow | Should -Match "needs\.changes\.outputs\.windows == 'true'"
        $workflow | Should -Match 'Taskfile\.yml'
        $workflow | Should -Match 'taskfiles/\*\*'
        $workflow | Should -Match 'PLATFORM_REQUIRED'
        $workflow | Should -Match 'check_platform'
        $workflow | Should -Not -Match 'success\|skipped'
        $workflow | Should -Match 'ref: \$\{\{ env\.TESTED_SHA \}\}'
    }
}
