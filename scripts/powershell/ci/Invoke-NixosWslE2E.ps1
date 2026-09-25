<#
.SYNOPSIS
    Run an isolated NixOS-WSL install and nixos-rebuild switch E2E check.

.DESCRIPTION
    This script is intended for a Windows GitHub Actions runner with WSL2
    enabled. It creates a temporary NixOS-WSL distro, runs the repository
    post-install flow, verifies that nixos-rebuild switch removed the first-run
    welcome banner, and unregisters the temporary distro unless -KeepDistro is set.
#>

[CmdletBinding()]
param(
    [string]$DistroName = "",
    [string]$InstallDir = "",
    [string]$ReleaseTag = "",
    [int]$PostInstallTimeoutSeconds = 7200,
    [switch]$KeepDistro
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$libPath = Join-Path $repoRoot "scripts\powershell\lib"

. (Join-Path $libPath "WindowsEnvironment.ps1")
Repair-WindowsSetupEnvironment
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")
. (Join-Path $repoRoot "scripts\powershell\handlers\Handler.NixOSWSL.ps1")
. (Join-Path $repoRoot "scripts\powershell\handlers\Handler.NixRebuild.ps1")
. (Join-Path $repoRoot "scripts\powershell\handlers\Handler.HermesAgent.ps1")

# The setup handler has legacy Invoke-Wsl calls without per-command timeouts.
# Bound those calls in this disposable E2E process; long post-install rebuilds
# keep using their explicit timeout from SetupContext.
$script:InvokeWslOriginal = (Get-Command Invoke-Wsl).ScriptBlock
function Invoke-Wsl {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -le 0) {
        $TimeoutSeconds = 900
    }

    & $script:InvokeWslOriginal -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
}

if ([string]::IsNullOrWhiteSpace($DistroName)) {
    $suffix = if ($env:GITHUB_RUN_ID) {
        "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
    }
    else {
        [guid]::NewGuid().ToString("N")
    }
    $DistroName = "NixOS-CI-$suffix"
}

if ($DistroName -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "DistroName contains unsupported characters: $DistroName"
}

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $tempRoot $DistroName
}

function Write-CiSection {
    param([Parameter(Mandatory)][string]$Title)

    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Host "::group::$Title"
    }
    else {
        Write-Host ""
        Write-Host "=== $Title ===" -ForegroundColor Cyan
    }
}

function Complete-CiSection {
    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Host "::endgroup::"
    }
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Roots
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $rootWithSeparator = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
        if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Remove-InstallDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $allowedRoots = @($env:RUNNER_TEMP, $env:TEMP) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not (Test-PathUnderRoot -Path $Path -Roots $allowedRoots)) {
        throw "Refusing to remove InstallDir outside runner temp directories: $Path"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Invoke-WslChecked {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 600,
        [switch]$AllowFailure
    )

    $output = @(Invoke-Wsl -TimeoutSeconds $TimeoutSeconds -Arguments $Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Host "  $line"
        }
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $detail = ($output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        throw "wsl $($Arguments -join ' ') failed with exit code $exitCode`n$detail"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function Write-WslRebuildDiagnostic {
    param([Parameter(Mandatory)][string]$Phase)

    Write-CiSection "WSL rebuild diagnostics: $Phase"
    try {
        $diagnosticScript = @'
set +e
echo '--- memory ---'
free -h
echo '--- filesystem ---'
df -h / /nix
echo '--- meminfo ---'
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
echo '--- nix-daemon ---'
systemctl status nix-daemon --no-pager 2>&1 | tail -n 40
echo '--- recent kernel messages ---'
dmesg --time-format iso 2>&1 | tail -n 100
'@
        $diagnosticScript = $diagnosticScript -replace "`r`n?", "`n"
        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc", $diagnosticScript
        ) -TimeoutSeconds 90 -AllowFailure | Out-Null
    }
    catch {
        Write-Warning "Could not collect WSL rebuild diagnostics ($Phase): $($_.Exception.Message)"
    }
    finally {
        Complete-CiSection
    }
}

function Remove-TemporaryDistro {
    param([Parameter(Mandatory)][string]$Name)

    Invoke-WslChecked -Arguments @("--terminate", $Name) -TimeoutSeconds 60 -AllowFailure | Out-Null
    Invoke-WslChecked -Arguments @("--unregister", $Name) -TimeoutSeconds 300 -AllowFailure | Out-Null
}

$installFullPath = [System.IO.Path]::GetFullPath($InstallDir)
if (-not (Test-PathUnderRoot -Path $installFullPath -Roots @($tempRoot))) {
    throw "InstallDir must be under RUNNER_TEMP or TEMP for safe cleanup: $installFullPath"
}

$createdDistro = $false

try {
    Write-CiSection "Preflight"
    try {
        Write-Host "Repository: $repoRoot"
        Write-Host "Distro:     $DistroName"
        Write-Host "InstallDir: $installFullPath"
        Invoke-WslChecked -Arguments @("--version") -TimeoutSeconds 60 | Out-Null
        Invoke-WslChecked -Arguments @("--status") -TimeoutSeconds 60 -AllowFailure | Out-Null
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Clean Previous Temporary State"
    try {
        Remove-TemporaryDistro -Name $DistroName
        Remove-InstallDirectory -Path $installFullPath
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Install NixOS-WSL"
    try {
        $context = [SetupContext]::new($repoRoot)
        $context.DistroName = $DistroName
        $context.InstallDir = $installFullPath
        $context.Options["ReleaseTag"] = $ReleaseTag
        $context.Options["PostInstallScript"] = Join-Path $repoRoot "scripts\sh\nixos-wsl-postinstall.sh"
        $context.Options["PostInstallTimeoutSeconds"] = $PostInstallTimeoutSeconds
        $context.Options["SyncMode"] = "repo"
        $context.Options["SyncBack"] = "none"
        $context.Options["StateVersion"] = "25.05"
        # Import CI's prebuilt system closures before executing the production
        # post-install script so both switches consume the same verified Nix
        # outputs instead of compiling them again inside the WSL runner.
        $context.Options["SkipPostInstallSetup"] = $true
        # The CI checkout is already pinned to TESTED_SHA. Do not let the
        # post-install flow perform an unrelated network flake update.
        $context.Options["SkipFlakeUpdate"] = $true

        $handler = [NixOSWSLHandler]::new()
        $createdDistro = $true
        $result = $handler.Apply($context)
        if (-not $result.Success) {
            throw "NixOS-WSL install failed: $($result.Message)"
        }
        Write-Host "CI_ASSERTION: production NixOSWSLHandler imported $DistroName before its post-install switch."
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Import prebuilt NixOS and Hermes closures"
    try {
        $artifactDir = Join-Path $env:RUNNER_TEMP "wsl-nix-cache-artifact"
        $cacheArchive = Join-Path $artifactDir "wsl-nix-cache.tar"
        $pathsFile = Join-Path $artifactDir "wsl-system-paths.txt"
        if (-not (Test-Path -LiteralPath $cacheArchive -PathType Leaf) -or
            -not (Test-Path -LiteralPath $pathsFile -PathType Leaf)) {
            throw "WSL prebuild artifact is incomplete: $artifactDir"
        }
        $systemPaths = @(Get-Content -LiteralPath $pathsFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($systemPaths.Count -ne 2 -or $systemPaths.Where({ $_ -notmatch '^/nix/store/[a-z0-9]{32}-' }).Count -ne 0) {
            throw "WSL prebuild artifact must contain exactly two Nix store paths: $($systemPaths -join ', ')"
        }

        $cacheDir = Join-Path $env:RUNNER_TEMP "wsl-nix-cache"
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        & tar.exe -xf $cacheArchive -C $cacheDir
        if ($LASTEXITCODE -ne 0) {
            throw "Could not extract WSL Nix cache artifact (exit $LASTEXITCODE)"
        }
        $cachePathResult = Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "wslpath", "-a", $cacheDir.Replace('\', '/')
        ) -TimeoutSeconds 60
        $cacheLinuxPath = ($cachePathResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -match '^/' } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($cacheLinuxPath)) {
            throw "Could not resolve WSL path for Nix cache artifact: $cacheDir"
        }

        $importCommand = "nix --extra-experimental-features 'nix-command flakes' copy --no-check-sigs --from 'file://$cacheLinuxPath' '$($systemPaths[0])' '$($systemPaths[1])' && nix --extra-experimental-features 'nix-command flakes' path-info '$($systemPaths[0])' '$($systemPaths[1])'"
        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc", $importCommand
        ) -TimeoutSeconds 1800 | Out-Null
        Write-Host "CI_ASSERTION: imported base and Hermes system closures from the Linux prebuild artifact."
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Run production NixOS-WSL post-install switch"
    try {
        $postInstallPath = [string]$context.Options["PostInstallScript"]
        $postInstallWslPathResult = Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "wslpath", "-a", $postInstallPath.Replace('\', '/')
        ) -TimeoutSeconds 60
        $postInstallWslPath = ($postInstallWslPathResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -match '^/' } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($postInstallWslPath)) {
            throw "Could not resolve WSL post-install script path: $postInstallPath"
        }
        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc", "bash '$postInstallWslPath' --sync-mode repo --sync-back none --state-version 25.05 --skip-flake-update"
        ) -TimeoutSeconds $PostInstallTimeoutSeconds | Out-Null
        Write-Host "CI_ASSERTION: production NixOS-WSL post-install switch completed for $DistroName."
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Verify authenticated Nix configuration reaches WSL"
    try {
        $authNixConfigCheck = @'
set -o pipefail
case "${NIX_CONFIG:-}" in
  *"access-tokens = github.com="*) echo "GitHub access-token config is available inside WSL." ;;
  *) echo "NIX_CONFIG is missing the GitHub access-token configuration inside WSL." >&2; exit 1 ;;
esac
if nix config show | grep max-jobs | grep 2 && nix config show | grep cores | grep 1; then
  echo "Nix builder limits are max-jobs=2 and cores=1."
else
  echo "Unexpected Nix builder limits; expected max-jobs=2 and cores=1." >&2
  exit 1
fi
'@
        $authNixConfigCheck = $authNixConfigCheck -replace "`r`n?", "`n"
        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc", $authNixConfigCheck
        ) -TimeoutSeconds 60 | Out-Null
        Write-Host "CI_ASSERTION: NIX_CONFIG GitHub access-token setting is available inside WSL."
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Verify nixos-rebuild switch"
    try {
        Invoke-WslChecked -Arguments @("--terminate", $DistroName) -TimeoutSeconds 60 -AllowFailure | Out-Null

        $welcomeCheck = Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "--",
            "bash", "-lc", "true"
        ) -TimeoutSeconds 300
        $welcomeText = $welcomeCheck.Output -join [Environment]::NewLine
        if ($welcomeText -match "Welcome to your new NixOS-WSL system") {
            throw "NixOS-WSL first-run welcome is still displayed; nixos-rebuild switch did not fully apply."
        }

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc",
            "test -f /home/nixos/.dotfiles/flake.nix && test -e /run/current-system/sw/bin/nixos-rebuild"
        ) -TimeoutSeconds 300 | Out-Null

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc",
            "nixos-rebuild list-generations | tail -n +2 && readlink -f /run/current-system"
        ) -TimeoutSeconds 300 | Out-Null

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "nixos", "--",
            "bash", "-lc",
            "command -v zsh && command -v chezmoi && command -v task && command -v git"
        ) -TimeoutSeconds 300 | Out-Null

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "nixos", "--",
            "bash", "-lc",
            'GH_TOKEN=ci TAVILY_API_KEY=ci GITHUB_WORK_TOKEN=ci zsh -ic "type z >/dev/null && bindkey" | rg "\"\^\[q\" __zoxide_zi_widget"'
        ) -TimeoutSeconds 300 | Out-Null

        Write-CiSection "Enable Hermes Agent through Nix"
        try {
            # Hermes' default package is large enough to trigger memory
            # pressure on the Windows runner while Nix evaluates/builds it.
            # The distro is disposable, so a bounded swap file is a safer
            # CI guardrail than raising parallelism and causing an OOM kill.
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "root", "--",
                "bash", "-lc",
                'if ! swapon --show=NAME --noheadings | grep -q .; then dd if=/dev/zero of=/swapfile bs=1M count=8192 status=none && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; fi && free -h'
            ) -TimeoutSeconds 300 | Out-Null

            # Seed the disposable distro with pre-existing Hermes state before
            # Home Manager activation. This proves activation preserves user
            # data and that the gateway can read a private provider env file.
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc",
                "install -d -m 700 /home/nixos/.hermes/memories && printf '%s\\n' 'OPENROUTER_API_KEY=ci' 'API_SERVER_ENABLED=true' 'API_SERVER_KEY=dotfiles-ci-health-probe' 'API_SERVER_PORT=18642' > /home/nixos/.hermes/.env && chmod 600 /home/nixos/.hermes/.env && printf '%s\\n' 'preserve-existing-hermes-state' > /home/nixos/.hermes/memories/dotfiles-ci-state-preservation.txt && chmod 600 /home/nixos/.hermes/memories/dotfiles-ci-state-preservation.txt"
            ) -TimeoutSeconds 60 | Out-Null

            $rebuildContext = [SetupContext]::new($repoRoot)
            $rebuildContext.DistroName = $DistroName
            $rebuildContext.Options["WithHermes"] = $true
            $rebuildContext.Options["SkipFlakeUpdate"] = $true
            $rebuildContext.Options["NixRebuildTimeoutSeconds"] = $PostInstallTimeoutSeconds
            $rebuildHandler = [NixRebuildHandler]::new()
            if (-not $rebuildHandler.CanApply($rebuildContext)) {
                throw "NixRebuildHandler cannot apply to the newly installed WSL distro $DistroName"
            }
            Write-WslRebuildDiagnostic -Phase "before Hermes rebuild"
            try {
                $rebuildResult = $rebuildHandler.Apply($rebuildContext)
                if (-not $rebuildResult.Success) {
                    throw "Nix-managed Hermes setup via NixRebuildHandler failed: $($rebuildResult.Message)"
                }
            }
            catch {
                Write-WslRebuildDiagnostic -Phase "after Hermes rebuild failure"
                throw
            }
            Write-Host "CI_ASSERTION: production NixRebuildHandler applied WithHermes to $DistroName."
            $hermesHandler = [HermesAgentHandler]::new()
            if (-not $hermesHandler.CanApply($rebuildContext)) {
                throw "HermesAgentHandler skipped validation after NixRebuildHandler completed for $DistroName"
            }
            $hermesResult = $hermesHandler.Apply($rebuildContext)
            if (-not $hermesResult.Success) {
                throw "Production HermesAgentHandler readiness validation failed: $($hermesResult.Message)"
            }
            Write-Host "CI_ASSERTION: production HermesAgentHandler verified its active Nix service and CLI."

            $hermesVerifier = @'
set -eu
if ! hermes_path="$(type -P hermes)" || [ -z "$hermes_path" ]; then
  echo 'Hermes CLI is missing from the NixOS user PATH' >&2
  exit 1
fi
hermes_store_path="$(readlink -f "$hermes_path")"
printf 'Hermes CLI path: %s\nResolved path: %s\n' "$hermes_path" "$hermes_store_path"
case "$hermes_store_path" in
  /nix/store/*) test -x "$hermes_store_path" ;;
  *) echo "Hermes CLI is not Nix-managed: $hermes_store_path" >&2; exit 1 ;;
esac
hermes --version
'@
            $hermesVerifier = $hermesVerifier -replace "`r`n?", "`n"
            $hermesVerifierBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($hermesVerifier))
            $hermesVerifierCommand = "set -o pipefail; printf '%s' '$hermesVerifierBase64' | base64 -d | bash"
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc", $hermesVerifierCommand
            ) -TimeoutSeconds 300 | Out-Null

            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc",
                "test `$(stat -c '%a' /home/nixos/.hermes/.env) = 600 && grep -qx 'OPENROUTER_API_KEY=ci' /home/nixos/.hermes/.env && grep -qx 'API_SERVER_ENABLED=true' /home/nixos/.hermes/.env && grep -qx 'API_SERVER_PORT=18642' /home/nixos/.hermes/.env && grep -qx 'preserve-existing-hermes-state' /home/nixos/.hermes/memories/dotfiles-ci-state-preservation.txt"
            ) -TimeoutSeconds 60 | Out-Null

            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "root", "--",
                "bash", "-lc", "loginctl show-user nixos -p Linger --value | grep -qx yes"
            ) -TimeoutSeconds 300 | Out-Null
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc", "systemctl --user is-enabled hermes-agent.service && systemctl --user is-active hermes-agent.service"
            ) -TimeoutSeconds 300 | Out-Null

            $readinessAttempts = 30
            $readinessCurlTimeoutSeconds = 2
            $readinessRetryDelaySeconds = 1
            $readinessTimeoutMarginSeconds = 30
            $readinessTimeoutSeconds = ($readinessAttempts * ($readinessCurlTimeoutSeconds + $readinessRetryDelaySeconds)) + $readinessTimeoutMarginSeconds
            $readinessCommand = @'
nix shell --inputs-from /home/nixos/.dotfiles nixpkgs#curl nixpkgs#jq --command bash -s <<'DOTFILES_HERMES_READINESS'
set -euo pipefail
health_url='http://127.0.0.1:18642/health/detailed'

expect_unauthorized() {
  local description="$1"
  shift
  local status_code
  local curl_exit_code

  for attempt in {1..__READINESS_ATTEMPTS__}; do
    if status_code=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time __READINESS_CURL_TIMEOUT_SECONDS__ "$@" "$health_url"); then
      curl_exit_code=0
    else
      curl_exit_code=$?
    fi

    if [[ $curl_exit_code -eq 0 && $status_code == 401 ]]; then
      return 0
    fi
    if [[ -n $status_code && $status_code != 000 ]]; then
      echo "Hermes $description probe expected HTTP 401 but received $status_code" >&2
      return 1
    fi

    if [[ $attempt -lt __READINESS_ATTEMPTS__ ]]; then
      sleep __READINESS_RETRY_DELAY_SECONDS__
    fi
  done

  echo "Hermes $description probe received no HTTP response after __READINESS_ATTEMPTS__ attempts (last curl exit code: $curl_exit_code)" >&2
  return 1
}

expect_unauthorized 'missing bearer token'
expect_unauthorized 'invalid bearer token' -H 'Authorization: Bearer invalid-dotfiles-ci-health-probe'

for attempt in {1..__READINESS_ATTEMPTS__}; do
  response=$(curl --fail --silent --show-error --max-time __READINESS_CURL_TIMEOUT_SECONDS__ \
    -H 'Authorization: Bearer dotfiles-ci-health-probe' "$health_url" 2>&1) || true
  if printf '%s' "$response" | jq -e '
    .status == "ok" and
    .readiness.status == "ok" and
    (.readiness.checks | type == "object" and length > 0 and all(.[]; .status == "ok")) and
    (.readiness.checks as $checks | all(
      ["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"][];
      . as $required | ($checks[$required] | type == "object" and .status == "ok")
    ))
  ' >/dev/null 2>&1; then
    printf '%s\n' "$response"
    exit 0
  fi
  sleep __READINESS_RETRY_DELAY_SECONDS__
done

echo "Hermes readiness did not report all required checks healthy: state_db, session_store, config, model, disk, gateway, background_queues" >&2
printf '%s\n' "$response" >&2
exit 1
DOTFILES_HERMES_READINESS
'@
            $readinessCommand = $readinessCommand.Replace('__READINESS_ATTEMPTS__', [string]$readinessAttempts)
            $readinessCommand = $readinessCommand.Replace('__READINESS_CURL_TIMEOUT_SECONDS__', [string]$readinessCurlTimeoutSeconds)
            $readinessCommand = $readinessCommand.Replace('__READINESS_RETRY_DELAY_SECONDS__', [string]$readinessRetryDelaySeconds)

            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc",
                $readinessCommand
            ) -TimeoutSeconds $readinessTimeoutSeconds | Out-Null
        }
        catch {
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc", "systemctl --user status --no-pager hermes-agent.service"
            ) -TimeoutSeconds 60 -AllowFailure | Out-Null
            Invoke-WslChecked -Arguments @(
                "-d", $DistroName, "-u", "nixos", "--",
                "bash", "-lc", "journalctl --user -u hermes-agent.service -n 100 --no-pager"
            ) -TimeoutSeconds 60 -AllowFailure | Out-Null
            throw
        }
        finally {
            Complete-CiSection
        }
    }
    finally {
        Complete-CiSection
    }
}
finally {
    if ($createdDistro -and -not $KeepDistro) {
        Write-CiSection "Cleanup"
        try {
            Remove-TemporaryDistro -Name $DistroName
            Remove-InstallDirectory -Path $installFullPath
        }
        finally {
            Complete-CiSection
        }
    }
    elseif ($KeepDistro) {
        Write-Host "Keeping temporary distro for debugging: $DistroName"
        Write-Host "InstallDir: $installFullPath"
    }
}
