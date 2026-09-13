[CmdletBinding()]
param(
    [ValidateSet("Sync", "Status")]
    [string]$Action = "Sync"
)

$ErrorActionPreference = "Stop"
$ProfileId = "dotfiles"

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

if ($Action -eq "Status") {
    Invoke-Docker -Arguments @("mcp", "profile", "show", $ProfileId)
    exit 0
}

& docker mcp profile show $ProfileId *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[mcp-toolkit] creating profile $ProfileId"
    Invoke-Docker -Arguments @("mcp", "profile", "create", "--id", $ProfileId, "--name", $ProfileId)
}

$ServerArguments = @("mcp", "profile", "server", "add", $ProfileId)
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
