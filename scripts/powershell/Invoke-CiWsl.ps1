# Native WSL adapters; the Taskfile owns preparation/activation/restart ordering.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Import', 'Apply', 'Restart', 'Verify', 'Cleanup')][string]$Phase,
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$TestedSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:GITHUB_ACTIONS -cne 'true') {
    throw 'WSL E2E adapters require a disposable native GitHub Actions Windows runner.'
}
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repository 'scripts/powershell/lib/Invoke-ExternalCommand.ps1')
. (Join-Path $repository 'scripts/powershell/lib/Invoke-NixosWslSetup.ps1')
$artifact = [IO.Path]::GetFullPath($ArtifactDirectory)
$ownerFile = Join-Path $artifact 'wsl-owner.json'
$distroName = 'NixOS'
if ($env:GITHUB_RUN_ID -notmatch '^[0-9]+$' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'A workflow run ID and runner temporary directory are required.'
}
$tempRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/')

function Assert-CiWslOwnership([string]$Root, [string]$Directory, [string]$Name, [string]$RunId, [string]$ExpectedRunId) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $directoryPath = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if ($Name -cne 'NixOS' -or $RunId -cne $ExpectedRunId -or
        -not $directoryPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($directoryPath) -notmatch '^NixOS-CI-[a-f0-9]{32}$') {
        throw 'Refusing an unsafe CI distro name or cleanup path.'
    }
}
function ConvertTo-CiWslArgument([string]$Value) {
    return "'" + $Value.Replace("'", "'\''") + "'"
}
function Invoke-CiWslCommand([string]$User, [string]$Source, [int]$TimeoutSeconds = 300) {
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Source -replace "`r`n?", "`n")))
    Invoke-Wsl -TimeoutSeconds $TimeoutSeconds -Arguments @(
        '-d', $distroName, '-u', $User, '--exec', 'bash', '-lc',
        "set -o pipefail; printf '%s' '$payload' | base64 -d | bash"
    ) | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "WSL E2E command failed (exit=$LASTEXITCODE)." }
}
function Resolve-CiWslPath([string]$Path) {
    $output = @(Invoke-Wsl -TimeoutSeconds 60 -Arguments @('-d', $distroName, '-u', 'root', '--exec', 'wslpath', '-a', $Path))
    $resolved = $output | ForEach-Object { ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() } |
        Where-Object { $_ -match '^/' } | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0 -or -not $resolved) { throw "Could not resolve WSL artifact path: $Path" }
    return $resolved
}

if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $ownerFile) { throw 'WSL E2E preparation requires a fresh artifact directory.' }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Invoke-NativeCommand -Command 'winget.exe' -Arguments @('install', '--id', 'Microsoft.WSL', '--exact', '--accept-source-agreements', '--accept-package-agreements', '--silent') | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the WSL runtime.' }
    }
    Invoke-Wsl -Arguments @('--version') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'WSL runtime is unavailable.' }
    Invoke-Wsl -Arguments @('--set-default-version', '2') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not select WSL2.' }
    $listed = @(Invoke-Wsl -TimeoutSeconds 30 -Arguments @('--list', '--quiet'))
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing WSL distributions.' }
    $existing = $listed | ForEach-Object { ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '') -split '\r?\n' } |
        ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($existing -contains $distroName) { throw 'Refusing to adopt or replace a pre-existing NixOS distro.' }
    $installDir = Join-Path $tempRoot ('NixOS-CI-' + [guid]::NewGuid().ToString('N'))
    Assert-CiWslOwnership -Root $tempRoot -Directory $installDir -Name $distroName -RunId $env:GITHUB_RUN_ID -ExpectedRunId $env:GITHUB_RUN_ID
    if (Test-Path -LiteralPath $installDir) { throw 'The CI distro install location already exists.' }
    New-Item -ItemType Directory -Path $artifact -Force | Out-Null
    # Record ownership before installation: cleanup can handle partial creation,
    # but it can never unregister a distro present before this stage.
    $owner = @{ schemaVersion = 1; distroName = $distroName; installDir = $installDir; runId = $env:GITHUB_RUN_ID }
    [IO.File]::WriteAllText($ownerFile, ($owner | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Install-NixosWsl -DistroName $distroName -InstallDir $installDir
    return
}

if (-not (Test-Path -LiteralPath $ownerFile)) {
    if ($Phase -eq 'Cleanup') { return }
    throw 'The WSL distro was not prepared by this workflow.'
}
$owner = Get-Content -LiteralPath $ownerFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($owner.schemaVersion -ne 1) { throw 'Unknown WSL ownership metadata.' }
Assert-CiWslOwnership -Root $tempRoot -Directory $owner.installDir -Name $owner.distroName -RunId $owner.runId -ExpectedRunId $env:GITHUB_RUN_ID

if ($Phase -eq 'Cleanup') {
    $listed = @(Invoke-Wsl -TimeoutSeconds 30 -Arguments @('--list', '--quiet'))
    if ($LASTEXITCODE -ne 0) { throw 'Cannot safely clean up without enumerating WSL distros.' }
    $existing = $listed | ForEach-Object { ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '') -split '\r?\n' } |
        ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($existing -contains $distroName) {
        Invoke-Wsl -Arguments @('--terminate', $distroName) -TimeoutSeconds 60 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Could not terminate the CI-created WSL distro.' }
        Invoke-Wsl -Arguments @('--unregister', $distroName) -TimeoutSeconds 300 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Could not unregister the CI-created WSL distro.' }
    }
    if (Test-Path -LiteralPath $owner.installDir) { Remove-Item -LiteralPath $owner.installDir -Recurse -Force }
    Remove-Item -LiteralPath $ownerFile -Force
    return
}

# Explicit WSL environment forwarding works from both stable PowerShell 5.1 and 7.
$forwarded = @($env:WSLENV -split ':' | Where-Object { $_ -and ($_ -split '/')[0] -notin @('GITHUB_TOKEN', 'GITHUB_WORKSPACE', 'RUNNER_TEMP') })
$env:WSLENV = (@($forwarded) + @('GITHUB_TOKEN/u', 'GITHUB_WORKSPACE/p', 'RUNNER_TEMP/p')) -join ':'
$wslArtifact = Resolve-CiWslPath -Path $artifact
$qArtifact = ConvertTo-CiWslArgument $wslArtifact

if ($Phase -eq 'Import') {
    foreach ($user in @('root', 'nixos')) {
        Invoke-CiWslCommand -User $user -Source 'set -euo pipefail; bash "$GITHUB_WORKSPACE/scripts/sh/configure-bootstrap-ci-nix.sh" --wsl'
    }
    $bootstrap = (Get-Content -LiteralPath (Join-Path $artifact 'bootstrap-python-path.txt') -Raw).Trim()
    if ($bootstrap -cnotmatch '^/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+$') { throw 'Invalid artifact Python bootstrap path.' }
    $qBootstrap = ConvertTo-CiWslArgument $bootstrap
    Invoke-CiWslCommand -User root -TimeoutSeconds 1800 -Source @"
set -euo pipefail
nix-store --realise --option max-jobs 0 --option builders '' --option fallback false $qBootstrap
$qBootstrap/bin/python3 -B "`$GITHUB_WORKSPACE/scripts/python/prepare_ci_nix_artifact.py" import --target wsl --tested-sha '$TestedSha' --input $qArtifact
"@
    [IO.File]::WriteAllText((Join-Path $artifact 'imported-sha.txt'), $TestedSha, [Text.UTF8Encoding]::new($false))
    return
}
if ((Get-Content -LiteralPath (Join-Path $artifact 'imported-sha.txt') -Raw).Trim() -cne $TestedSha) {
    throw 'The WSL artifact was not verified for this source SHA.'
}
$roots = Get-Content -LiteralPath (Join-Path $artifact 'roots.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($path in @($roots.source, $roots.system)) {
    if ($path -cnotmatch '^/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+$') { throw 'Invalid imported WSL root.' }
}
$qSystem = ConvertTo-CiWslArgument $roots.system
$qSource = ConvertTo-CiWslArgument $roots.source

switch ($Phase) {
    'Apply' {
        Invoke-CiWslCommand -User nixos -Source @'
set -euo pipefail
umask 077
mkdir -p ~/.hermes
printf '%s\n' 'OPENROUTER_API_KEY=ci' 'API_SERVER_ENABLED=true' 'API_SERVER_KEY=dotfiles-ci-health-probe' 'API_SERVER_PORT=18642' > ~/.hermes/.env
chmod 600 ~/.hermes/.env
'@
        Invoke-NixosWslSetup -Repository $repository -DistroName $distroName -SyncMode repo -SyncBack none -TimeoutSeconds 7200 -FlakeReference ('path:' + $roots.source + '#nixos') -SourceDirectory $roots.source -AllowBuilds $false
        Invoke-CiWslCommand -User root -Source @"
set -euo pipefail
test "`$(readlink -f /run/current-system)" = $qSystem
diff -qr $qSource /home/nixos/.dotfiles
"@
    }
    'Restart' {
        Invoke-Wsl -Arguments @('--terminate', $distroName) -TimeoutSeconds 60 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'WSL cold restart failed.' }
        # Starting a new command boots the distro. Do not restart Hermes here:
        # Verify must observe whether the enabled service starts on its own.
        Invoke-CiWslCommand -User root -TimeoutSeconds 360 -Source "set -euo pipefail; test `"`$(readlink -f /run/current-system)`" = $qSystem"
    }
    'Verify' {
        Invoke-CiWslCommand -User nixos -TimeoutSeconds 720 -Source @"
set -euo pipefail
trap 'status=`$?; if (( status != 0 )); then journalctl --user -u hermes-agent.service --no-pager -n 80 >&2; fi' EXIT
test "`$(readlink -f /run/current-system)" = $qSystem
hermes --version
# Wait only for ordinary boot activation, not a repair/restart command.
export NIX_CONFIG=`$'max-jobs = 0\nbuilders =\nfallback = false'
nix shell --inputs-from $qSource nixpkgs#curl nixpkgs#jq --command bash -s <<'READINESS'
set -euo pipefail
url='http://127.0.0.1:18642/health/detailed'
deadline=`$((SECONDS + 300))
while :; do
  if response=`$(curl --fail --silent --show-error --max-time 2 -H 'Authorization: Bearer dotfiles-ci-health-probe' "`$url" 2>&1) &&
      printf '%s' "`$response" | jq -e '
        .status == "ok" and .readiness.status == "ok" and
        (.readiness.checks | type == "object" and all(.[]; .status == "ok")) and
        (.readiness.checks as `$checks | all(
          ["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"][];
          . as `$required | `$checks[`$required].status == "ok"))' >/dev/null 2>&1; then break; fi
  if (( SECONDS >= deadline )); then printf '%s\n' "`$response" >&2; exit 1; fi
  sleep 1
done
printf '%s\n' "`$response"
systemctl --user is-active hermes-agent.service
READINESS
"@
    }
}
