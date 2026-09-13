[CmdletBinding()]
param(
    [ValidateSet("Sync", "Push", "Pull", "Status")]
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

switch ($Action) {
    "Sync" { Sync-Profile }
    "Push" { Push-Profile }
    "Pull" { Pull-Profile }
    "Status" { Invoke-Docker -Arguments @("mcp", "profile", "show", $ProfileId) }
}
