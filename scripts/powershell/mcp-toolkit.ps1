[CmdletBinding()]
param(
    [ValidateSet("Sync", "Push", "Pull", "Secrets", "Status")]
    [string]$Action = "Sync"
)

$ErrorActionPreference = "Stop"
$ProfileId = "dotfiles"
$ProfileRef = if ([string]::IsNullOrWhiteSpace($env:MCP_TOOLKIT_PROFILE_REF)) {
    "ghcr.io/rurusasu/dotfiles/mcp-profile:latest"
}
else {
    $env:MCP_TOOLKIT_PROFILE_REF
}
$SecretAccount = if ([string]::IsNullOrWhiteSpace($env:MCP_TOOLKIT_OP_ACCOUNT)) {
    "my.1password.com"
}
else {
    $env:MCP_TOOLKIT_OP_ACCOUNT
}
$SecretTimeoutSeconds = if ([string]::IsNullOrWhiteSpace($env:MCP_TOOLKIT_OP_TIMEOUT_SECONDS)) {
    15
}
else {
    [int]$env:MCP_TOOLKIT_OP_TIMEOUT_SECONDS
}

$SecretRefs = [ordered]@{
    "exa.api_key"                  = "op://openclaw/ExaUsedOpenclawPAT/credential"
    "firecrawl.api_key"            = "op://openclaw/FirecrawlUsedOpenclawPAT/credential"
    "github.personal_access_token" = "op://openclaw/GitHubUsedOpenClawPAT/credential"
    "tavily.api_token"             = "op://openclaw/TavilyUsedOpenclawPAT/credential"
}
$ToolkitClients = @(
    "codex",
    "cursor",
    "gemini",
    "vscode",
    "zed"
)

$CatalogRefs = @(
    "catalog://mcp/docker-mcp-catalog/context7",
    "catalog://mcp/docker-mcp-catalog/deepwiki",
    "catalog://mcp/docker-mcp-catalog/exa",
    "catalog://mcp/docker-mcp-catalog/firecrawl",
    "catalog://mcp/docker-mcp-catalog/github-official",
    "catalog://mcp/docker-mcp-catalog/obsidian",
    "catalog://mcp/docker-mcp-catalog/playwright",
    "catalog://mcp/docker-mcp-catalog/tavily"
)

$StaleServers = @(
    "github",
    "linear",
    "sentry",
    "cloud-run",
    "superlocalmemory",
    "qmd",
    "hindsight"
)

function Invoke-Docker {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker is required"
}

& docker mcp --help *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker MCP Toolkit CLI is required"
}

function Sync-Profile {
    & docker mcp profile show $ProfileId *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[mcp-toolkit] creating profile $ProfileId"
        Invoke-Docker -Arguments @("mcp", "profile", "create", "--id", $ProfileId, "--name", $ProfileId)
    }

    $ServerArguments = @( "mcp", "profile", "server", "add", $ProfileId )
    foreach ($Ref in $CatalogRefs) {
        $ServerArguments += @("--server", $Ref)
    }
    Write-Host "[mcp-toolkit] converging catalog servers"
    Invoke-Docker -Arguments $ServerArguments

    foreach ($Stale in $StaleServers) {
        & docker mcp profile server remove $ProfileId --name $Stale *> $null
    }

    Write-Host "[mcp-toolkit] profile $ProfileId"
    Invoke-Docker -Arguments @("mcp", "profile", "show", $ProfileId)
}

function Push-Profile {
    Sync-Profile
    Write-Host "[mcp-toolkit] pushing $ProfileId to $ProfileRef"
    Invoke-Docker -Arguments @("mcp", "profile", "push", $ProfileId, $ProfileRef)
}

function Pull-Profile {
    Write-Host "[mcp-toolkit] pulling profile from $ProfileRef"
    Invoke-Docker -Arguments @("mcp", "profile", "pull", $ProfileRef)
    Write-Host "[mcp-toolkit] profile $ProfileId"
    Invoke-Docker -Arguments @("mcp", "profile", "show", $ProfileId)
}

function Get-OnePasswordSecret {
    param([Parameter(Mandatory)][string]$Reference)

    $opCommand = Get-Command op.exe -ErrorAction SilentlyContinue
    if (-not $opCommand) {
        $opCommand = Get-Command op -ErrorAction SilentlyContinue
    }
    if (-not $opCommand) {
        throw "1Password CLI (op) is required"
    }

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $opArguments = @("read", "--no-newline", "--account", $SecretAccount, $Reference)
        if ($opCommand.Name -eq "op.exe") {
            $opArguments = @("--cache=false") + $opArguments
        }

        $process = Start-Process -FilePath $opCommand.Source -ArgumentList $opArguments `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        if (-not $process.WaitForExit($SecretTimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "1Password read timed out for $Reference"
        }
        if ($process.ExitCode -ne 0) {
            throw "1Password read failed for $Reference"
        }

        return [System.IO.File]::ReadAllText($stdoutPath)
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Sync-Secrets {
    foreach ($Entry in $SecretRefs.GetEnumerator()) {
        Write-Host "[mcp-toolkit] injecting $($Entry.Key) from 1Password"
        $secret = Get-OnePasswordSecret -Reference $Entry.Value
        try {
            $secret | & docker mcp secret set $Entry.Key *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "Docker MCP secret injection failed for $($Entry.Key)"
            }
        }
        finally {
            $secret = $null
        }
    }
}

function Connect-Clients {
    foreach ($Client in $ToolkitClients) {
        Write-Host "[mcp-toolkit] connecting $Client to profile $ProfileId"
        Invoke-Docker -Arguments @("mcp", "client", "connect", "--global", "--profile", $ProfileId, "--quiet", $Client)
    }
}

switch ($Action) {
    "Sync" { Sync-Profile }
    "Push" { Push-Profile }
    "Pull" { Pull-Profile }
    "Secrets" { Sync-Secrets }
    "Clients" { Connect-Clients }
    "Status" { Invoke-Docker -Arguments @("mcp", "profile", "show", $ProfileId) }
}
