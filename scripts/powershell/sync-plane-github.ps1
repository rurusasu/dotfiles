[CmdletBinding()]
param(
    [string]$ConfigPath = ""
)

function Get-DefaultPlaneGithubSyncConfigPath {
    [CmdletBinding()]
    param()

    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($homeDir)) {
        throw "Cannot determine home directory for Plane GitHub sync config."
    }

    return (Join-Path (Join-Path $homeDir ".config") "plane-github-sync/config.json")
}

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    return $null
}

function Resolve-PlaneGithubValue {
    [CmdletBinding()]
    param(
        [object]$Value,
        [string]$Name = "value"
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = ([string]$Value).Trim()
    $match = [regex]::Match($text, '^\$\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\}$')
    if (-not $match.Success) {
        return $text
    }

    $envName = $match.Groups["name"].Value
    $envValue = [Environment]::GetEnvironmentVariable($envName)
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        throw "Environment variable '$envName' is required for Plane GitHub sync $Name."
    }

    return $envValue
}

function Expand-PlaneGithubEnvironmentVariables {
    [CmdletBinding()]
    param(
        [object]$Value,
        [string]$Name = "value"
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = ([string]$Value).Trim()
    $expanded = [regex]::Replace($text, '\$\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\}', {
        param([System.Text.RegularExpressions.Match]$Match)

        $envName = $Match.Groups["name"].Value
        $envValue = [Environment]::GetEnvironmentVariable($envName)
        if ([string]::IsNullOrWhiteSpace($envValue)) {
            throw "Environment variable '$envName' is required for Plane GitHub sync $Name."
        }

        return $envValue
    })

    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Get-PlaneGithubSyncConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Plane GitHub sync config was not found: $Path"
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $config.planeBaseUrl = Resolve-PlaneGithubValue -Value $config.planeBaseUrl -Name "planeBaseUrl"
    $config.planeWorkspaceSlug = Resolve-PlaneGithubValue -Value $config.planeWorkspaceSlug -Name "planeWorkspaceSlug"

    if ([string]::IsNullOrWhiteSpace($config.planeBaseUrl)) {
        throw "Plane GitHub sync config requires planeBaseUrl."
    }

    if ([string]::IsNullOrWhiteSpace($config.planeWorkspaceSlug)) {
        throw "Plane GitHub sync config requires planeWorkspaceSlug."
    }

    if ($null -eq $config.projectMappings) {
        throw "Plane GitHub sync config requires projectMappings."
    }

    return $config
}

function Get-PlaneGithubSyncStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $configDirectory = Split-Path -Path $ConfigPath -Parent
    $statePath = Expand-PlaneGithubEnvironmentVariables -Value (Get-ObjectPropertyValue -InputObject $Config -Names @("statePath")) -Name "statePath"
    if ([string]::IsNullOrWhiteSpace($statePath)) {
        if ([string]::IsNullOrWhiteSpace($configDirectory)) {
            return "state.json"
        }

        return (Join-Path $configDirectory "state.json")
    }

    return $statePath
}

function New-PlaneGithubSyncState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        version = 1
        links = New-Object -TypeName psobject
    }
}

function Get-PlaneGithubSyncState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (New-PlaneGithubSyncState)
    }

    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $state.PSObject.Properties["version"]) {
        Add-Member -InputObject $state -NotePropertyName "version" -NotePropertyValue 1
    } elseif ($null -eq $state.version) {
        $state.version = 1
    }

    if ($null -eq $state.PSObject.Properties["links"]) {
        Add-Member -InputObject $state -NotePropertyName "links" -NotePropertyValue (New-Object -TypeName psobject)
    } elseif ($null -eq $state.links) {
        $state.links = New-Object -TypeName psobject
    }

    return $state
}

function Get-PlaneGithubSyncStateKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl
    )

    return "$Repository|$GitHubIssueUrl"
}

function Get-PlaneGithubSyncStateLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl
    )

    if ($null -eq $State.links) {
        return $null
    }

    $key = Get-PlaneGithubSyncStateKey -Repository $Repository -GitHubIssueUrl $GitHubIssueUrl
    $property = $State.links.PSObject.Properties[$key]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Set-PlaneGithubSyncStateLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl,
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($null -eq $State.links) {
        Add-Member -InputObject $State -NotePropertyName "links" -NotePropertyValue (New-Object -TypeName psobject) -Force
    }

    $key = Get-PlaneGithubSyncStateKey -Repository $Repository -GitHubIssueUrl $GitHubIssueUrl
    Add-Member -InputObject $State.links -NotePropertyName $key -NotePropertyValue ([pscustomobject]$Value) -Force
}

function Save-PlaneGithubSyncState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PlaneGithubFingerprint {
    [CmdletBinding()]
    param(
        [string]$Title = "",
        [string]$Body = "",
        [bool]$Closed = $false
    )

    $normalizedTitle = ([string]$Title).Trim() -replace "`r`n?", "`n"
    $normalizedBody = ([string]$Body).Trim() -replace "`r`n?", "`n"
    $state = if ($Closed) { "closed" } else { "open" }
    $payload = @($normalizedTitle, $normalizedBody, $state) -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)

    return [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function Get-PlaneApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $inlineToken = Resolve-PlaneGithubValue -Value (Get-ObjectPropertyValue -InputObject $Config -Names @("planeApiToken")) -Name "planeApiToken"
    if (-not [string]::IsNullOrWhiteSpace($inlineToken)) {
        return $inlineToken
    }

    if (-not [string]::IsNullOrWhiteSpace($env:PLANE_API_KEY)) {
        return $env:PLANE_API_KEY
    }

    $tokenRef = Resolve-PlaneGithubValue -Value (Get-ObjectPropertyValue -InputObject $Config -Names @("planeApiTokenRef")) -Name "planeApiTokenRef"
    if ([string]::IsNullOrWhiteSpace($tokenRef)) {
        throw "Plane API token is required. Set planeApiTokenRef or PLANE_API_KEY."
    }

    if (-not (Get-Command -Name "op" -ErrorAction SilentlyContinue)) {
        throw "1Password CLI 'op' is required to read Plane API token ref."
    }

    $opArgs = @("read")
    $opAccount = Resolve-PlaneGithubValue -Value (Get-ObjectPropertyValue -InputObject $Config -Names @("opAccount")) -Name "opAccount"
    if (-not [string]::IsNullOrWhiteSpace($opAccount)) {
        $opArgs += @("--account", $opAccount)
    }
    $opArgs += $tokenRef

    $output = & op @opArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read Plane API token from 1Password."
    }

    $token = (($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Plane API token from 1Password was empty."
    }

    return $token
}

function Invoke-PlaneApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Get", "Post", "Patch", "Delete")]
        [string]$Method,
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [string]$Path,
        [hashtable]$Body = $null
    )

    $baseUrl = ([string]$Config.planeBaseUrl).TrimEnd("/")
    $workspaceSlug = [System.Uri]::EscapeDataString([string]$Config.planeWorkspaceSlug)
    $relativePath = $Path.TrimStart("/")
    $uri = "$baseUrl/api/v1/workspaces/$workspaceSlug/$relativePath"
    $headers = @{
        "Accept" = "application/json"
        "X-API-Key" = $Token
    }

    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -ContentType "application/json" -Body $json -ErrorAction Stop
    }

    return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -ErrorAction Stop
}

function Get-PlaneApiResponseItems {
    [CmdletBinding()]
    param(
        [object]$Response
    )

    if ($null -eq $Response) {
        return @()
    }

    if ($Response -is [array]) {
        return @($Response)
    }

    foreach ($propertyName in @("results", "data", "items")) {
        $property = $Response.PSObject.Properties[$propertyName]
        if ($null -ne $property) {
            return @($property.Value)
        }
    }

    return @($Response)
}

function Get-PlaneApiCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $response = Invoke-PlaneApi -Method "Get" -Config $Config -Token $Token -Path $Path
    return @(Get-PlaneApiResponseItems -Response $response)
}

function Normalize-PlaneProjectToken {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ([regex]::Replace(([string]$Value).ToLowerInvariant(), '[^a-z0-9]', ''))
}

function Test-PlaneProjectMatchesMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$Mapping
    )

    $mappingToken = Get-ObjectPropertyValue -InputObject $Mapping -Names @(
        "planeProject",
        "planeProjectIdentifier",
        "planeProjectSlug",
        "planeProjectName"
    )

    $normalizedMapping = Normalize-PlaneProjectToken -Value $mappingToken
    if ([string]::IsNullOrWhiteSpace($normalizedMapping)) {
        return $false
    }

    $projectTokens = @(
        Get-ObjectPropertyValue -InputObject $Project -Names @("identifier")
        Get-ObjectPropertyValue -InputObject $Project -Names @("slug")
        Get-ObjectPropertyValue -InputObject $Project -Names @("name")
        Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    )

    foreach ($token in $projectTokens) {
        if ((Normalize-PlaneProjectToken -Value $token) -eq $normalizedMapping) {
            return $true
        }
    }

    return $false
}

function Find-PlaneProjectForMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Projects,
        [Parameter(Mandatory)]
        [object]$Mapping
    )

    foreach ($project in $Projects) {
        if (Test-PlaneProjectMatchesMapping -Project $project -Mapping $Mapping) {
            return $project
        }
    }

    return $null
}

function Get-PlaneWorkItemDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $description = Get-ObjectPropertyValue -InputObject $WorkItem -Names @(
        "description_html",
        "description",
        "description_stripped"
    )

    if ($null -eq $description) {
        return ""
    }

    return [string]$description
}

function Get-PlaneWorkItemIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $identifier = Get-ObjectPropertyValue -InputObject $WorkItem -Names @(
        "identifier",
        "issue_identifier",
        "work_item_identifier"
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$identifier)) {
        return [string]$identifier
    }

    $sequenceId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("sequence_id")
    $projectIdentifier = Get-ObjectPropertyValue -InputObject $Project -Names @("identifier", "slug", "name")
    if ($null -ne $sequenceId -and -not [string]::IsNullOrWhiteSpace([string]$projectIdentifier)) {
        return "$projectIdentifier-$sequenceId"
    }

    return [string](Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id"))
}

function Get-PlaneWorkItemTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $title = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("name", "title")
    if ([string]::IsNullOrWhiteSpace([string]$title)) {
        $id = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id")
        return "Plane work item $id"
    }

    return [string]$title
}

function Get-PlainTextFromHtml {
    [CmdletBinding()]
    param(
        [string]$Html
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ""
    }

    $withoutTags = [regex]::Replace($Html, '<[^>]+>', ' ')
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    return ([regex]::Replace($decoded, '\s+', ' ')).Trim()
}

function Test-WorkItemLinkedToGitHub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [Parameter(Mandatory)]
        [string]$Repository
    )

    $externalSource = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("external_source")
    $externalId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("external_id")
    if ([string]$externalSource -eq "github" -and -not [string]::IsNullOrWhiteSpace([string]$externalId)) {
        return $true
    }

    $linkedFields = @(
        Get-PlaneWorkItemDescription -WorkItem $WorkItem
        $externalId
    )
    $repoIssuePattern = [regex]::Escape("https://github.com/$Repository/issues/")

    foreach ($field in $linkedFields) {
        $text = [string]$field
        if ($text -match '<!--\s*plane-github-sync:' -or $text -match $repoIssuePattern) {
            return $true
        }
    }

    return $false
}

function Get-PlaneWorkItemUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $baseUrl = ([string]$Config.planeBaseUrl).TrimEnd("/")
    $workspaceSlug = [string]$Config.planeWorkspaceSlug
    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    $workItemId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id")
    return "$baseUrl/$workspaceSlug/projects/$projectId/issues/$workItemId"
}

function Get-PlaneGithubIssueMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $workItemId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id")
    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    return "<!-- plane-github-sync: workspace=$($Config.planeWorkspaceSlug); project_id=$projectId; work_item_id=$workItemId -->"
}

function Get-GitHubIssueBodySyncMarker {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        return ""
    }

    $match = [regex]::Match(
        [string]$Body,
        '<!--\s*plane-github-sync:.*?-->',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        return ""
    }

    return $match.Value
}

function Get-GitHubIssueBodyWithSyncMarker {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Body = $null,
        [AllowNull()]
        [object]$ExistingBody = $null,
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $marker = Get-GitHubIssueBodySyncMarker -Body $ExistingBody
    if ([string]::IsNullOrWhiteSpace($marker)) {
        $marker = Get-PlaneGithubIssueMarker -Config $Config -Project $Project -WorkItem $WorkItem
    }

    $bodyText = if ($null -eq $Body) { "" } else { [string]$Body }
    $cleanBody = [regex]::Replace(
        $bodyText,
        '\s*<!--\s*plane-github-sync:.*?-->\s*',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    ).TrimEnd()
    if ([string]::IsNullOrWhiteSpace($cleanBody)) {
        return $marker
    }

    return "$cleanBody`n`n$marker"
}

function New-PlaneGithubIssueBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $projectName = Get-ObjectPropertyValue -InputObject $Project -Names @("name", "identifier", "slug")
    $identifier = Get-PlaneWorkItemIdentifier -Project $Project -WorkItem $WorkItem
    $description = Get-PlainTextFromHtml -Html (Get-PlaneWorkItemDescription -WorkItem $WorkItem)
    $planeUrl = Get-PlaneWorkItemUrl -Config $Config -Project $Project -WorkItem $WorkItem

    $lines = @(
        "Synced from Plane work item.",
        "",
        "- Plane: $planeUrl",
        "- Plane identifier: $identifier",
        "- Plane project: $projectName"
    )

    if (-not [string]::IsNullOrWhiteSpace($description)) {
        $lines += @("", "Plane description:", "", $description)
    }

    $lines += @(
        "",
        (Get-PlaneGithubIssueMarker -Config $Config -Project $Project -WorkItem $WorkItem)
    )

    return ($lines -join "`n")
}

function Invoke-GitHubIssueCreate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Body
    )

    if (-not (Get-Command -Name "gh" -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 'gh' is required to create issues."
    }

    $ghArgs = @(
        "api",
        "repos/$Repository/issues",
        "--method",
        "POST",
        "-f",
        "title=$Title",
        "-f",
        "body=$Body",
        "--jq",
        ".html_url"
    )

    $output = & gh @ghArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub issue in $Repository."
    }

    $issueUrl = (($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace([string]$issueUrl)) {
        throw "GitHub issue was created but no URL was returned."
    }

    return [string]$issueUrl
}

function Invoke-GitHubIssueList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository
    )

    if (-not (Get-Command -Name "gh" -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 'gh' is required to list issues."
    }

    $ghArgs = @(
        "api",
        "repos/$Repository/issues",
        "--method",
        "GET",
        "-f",
        "state=all",
        "--paginate",
        "--slurp"
    )

    $output = & gh @ghArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list GitHub issues in $Repository."
    }

    $json = (($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return @()
    }

    $pages = $json | ConvertFrom-Json
    if ($null -eq $pages) {
        return @()
    }

    $issues = @()
    foreach ($page in @($pages)) {
        if ($null -eq $page) {
            continue
        }

        if ($page -is [array]) {
            $issues += @($page)
        } else {
            $issues += $page
        }
    }

    return @($issues)
}

function Get-GitHubSyncableIssues {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Issues = @()
    )

    if ($null -eq $Issues) {
        return @()
    }

    return @($Issues | Where-Object { $null -ne $_ -and $null -eq $_.PSObject.Properties["pull_request"] })
}

function Invoke-GitHubIssuePatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [int]$Number,
        [Parameter(Mandatory)]
        [ValidateSet("open", "closed")]
        [string]$State,
        [string]$Title = "",
        [AllowNull()]
        [object]$Body = $null
    )

    if (-not (Get-Command -Name "gh" -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 'gh' is required to update issues."
    }

    $ghArgs = @(
        "api",
        "repos/$Repository/issues/$Number",
        "--method",
        "PATCH",
        "-f",
        "state=$State"
    )

    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $ghArgs += @("-f", "title=$Title")
    }

    if ($null -ne $Body) {
        $ghArgs += @("-f", "body=$Body")
    }

    $output = & gh @ghArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update GitHub issue #$Number in $Repository."
    }

    $json = (($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return [pscustomobject]@{}
    }

    return ($json | ConvertFrom-Json)
}

function Update-GitHubIssueFromPlane {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [int]$IssueNumber,
        [Parameter(Mandatory)]
        [string]$Title,
        [AllowNull()]
        [object]$Body = $null,
        [bool]$Closed = $false
    )

    $state = if ($Closed) { "closed" } else { "open" }
    return Invoke-GitHubIssuePatch -Repository $Repository -Number $IssueNumber -Title $Title -Body $Body -State $state
}

function Add-GitHubLinkToPlaneDescription {
    [CmdletBinding()]
    param(
        [string]$DescriptionHtml,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl
    )

    $encodedUrl = [System.Net.WebUtility]::HtmlEncode($GitHubIssueUrl)
    $marker = "<p>GitHub Issue: <a href=`"$encodedUrl`">$encodedUrl</a></p><!-- plane-github-sync: github-issue=$encodedUrl -->"

    if ([string]::IsNullOrWhiteSpace($DescriptionHtml)) {
        return $marker
    }

    return "$DescriptionHtml`n$marker"
}

function Get-PlaneProjectStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [object]$Project
    )

    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    return @(Get-PlaneApiCollection -Config $Config -Token $Token -Path "projects/$projectId/states/")
}

function Find-PlaneStateForGitHubState {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$States = @(),
        [Parameter(Mandatory)]
        [ValidateSet("open", "closed")]
        [string]$GitHubState
    )

    if ($null -eq $States) {
        return $null
    }

    if ($GitHubState -eq "closed") {
        foreach ($state in $States) {
            if ([string](Get-ObjectPropertyValue -InputObject $state -Names @("group")) -eq "completed") {
                return $state
            }
        }

        return $null
    }

    foreach ($group in @("unstarted", "backlog", "started")) {
        foreach ($state in $States) {
            if ([string](Get-ObjectPropertyValue -InputObject $state -Names @("group")) -eq $group) {
                return $state
            }
        }
    }

    return $null
}

function Convert-GitHubBodyToPlaneDescriptionHtml {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Body = $null,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl
    )

    $bodyText = ([string]$Body) -replace "`r`n?", "`n"
    $encodedBody = [System.Net.WebUtility]::HtmlEncode($bodyText) -replace "`n", "<br />`n"
    $encodedUrl = [System.Net.WebUtility]::HtmlEncode($GitHubIssueUrl)
    $html = @()

    if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
        $html += "<p>$encodedBody</p>"
    }

    $html += "<p>GitHub Issue: <a href=`"$encodedUrl`">$encodedUrl</a></p>"
    $html += "<!-- plane-github-sync: github-issue=$encodedUrl -->"

    return ($html -join "`n")
}

function New-PlaneWorkItemFromGitHubIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$Issue,
        [AllowNull()]
        [object[]]$States = @()
    )

    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    $githubIssueUrl = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("html_url", "url"))
    $githubState = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("state"))
    $state = Find-PlaneStateForGitHubState -States $States -GitHubState $githubState
    $body = @{
        name = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("title", "name"))
        description_html = Convert-GitHubBodyToPlaneDescriptionHtml -Body (Get-ObjectPropertyValue -InputObject $Issue -Names @("body")) -GitHubIssueUrl $githubIssueUrl
        external_source = "github"
        external_id = $githubIssueUrl
    }

    if ($null -ne $state) {
        $body.state = Get-ObjectPropertyValue -InputObject $state -Names @("id")
    }

    return Invoke-PlaneApi -Method "Post" -Config $Config -Token $Token -Path "projects/$projectId/work-items/" -Body $body
}

function Update-PlaneWorkItemGitHubLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [Parameter(Mandatory)]
        [string]$GitHubIssueUrl
    )

    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    $workItemId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id")
    $descriptionHtml = Add-GitHubLinkToPlaneDescription -DescriptionHtml (Get-PlaneWorkItemDescription -WorkItem $WorkItem) -GitHubIssueUrl $GitHubIssueUrl

    $body = @{
        description_html = $descriptionHtml
        external_source = "github"
        external_id = $GitHubIssueUrl
    }

    Invoke-PlaneApi -Method "Patch" -Config $Config -Token $Token -Path "projects/$projectId/work-items/$workItemId/" -Body $body | Out-Null
}

function Get-GitHubIssueNumberFromUrl {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Url = ""
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return 0
    }

    $match = [regex]::Match($Url, '/issues/(?<number>\d+)(?:[/?#]|$)')
    if (-not $match.Success) {
        return 0
    }

    return [int]$match.Groups["number"].Value
}

function Get-GitHubIssueIdentityKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [AllowNull()]
        [string]$Url = ""
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }

    $normalizedRepository = ([string]$Repository).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalizedRepository)) {
        return ""
    }

    $patterns = @(
        '^https://github\.com/(?<repository>[^/]+/[^/]+)/issues/(?<number>\d+)(?:[/?#]|$)',
        '^https://api\.github\.com/repos/(?<repository>[^/]+/[^/]+)/issues/(?<number>\d+)(?:[/?#]|$)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Url.Trim(), $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success -and $match.Groups["repository"].Value.ToLowerInvariant() -eq $normalizedRepository) {
            return "$normalizedRepository#$([int]$match.Groups["number"].Value)"
        }
    }

    return ""
}

function Get-GitHubIssueIdentityKeyFromText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [AllowNull()]
        [string]$Text = ""
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $escapedRepository = [regex]::Escape($Repository)
    $patterns = @(
        "https://github\.com/$escapedRepository/issues/(?<number>\d+)\b",
        "https://api\.github\.com/repos/$escapedRepository/issues/(?<number>\d+)\b"
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return "$($Repository.ToLowerInvariant())#$([int]$match.Groups["number"].Value)"
        }
    }

    return ""
}

function Get-PlaneWorkItemGitHubIssueUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem
    )

    $externalSource = [string](Get-ObjectPropertyValue -InputObject $WorkItem -Names @("external_source"))
    $externalId = [string](Get-ObjectPropertyValue -InputObject $WorkItem -Names @("external_id"))
    if ($externalSource.ToLowerInvariant() -eq "github" -and -not [string]::IsNullOrWhiteSpace($externalId)) {
        return $externalId
    }

    return ""
}

function Test-PlaneWorkItemClosed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [AllowNull()]
        [object[]]$States = @()
    )

    if ($null -eq $States) {
        return $false
    }

    $stateId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("state", "state_id")
    if ($null -ne $stateId -and $null -ne $stateId.PSObject.Properties["id"]) {
        $stateId = $stateId.id
    }

    foreach ($state in $States) {
        $id = Get-ObjectPropertyValue -InputObject $state -Names @("id")
        if ([string]$id -ne [string]$stateId) {
            continue
        }

        $group = ([string](Get-ObjectPropertyValue -InputObject $state -Names @("group"))).ToLowerInvariant()
        return ($group -eq "completed" -or $group -eq "cancelled")
    }

    return $false
}

function Update-PlaneWorkItemFromGitHubIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [Parameter(Mandatory)]
        [object]$Issue,
        [AllowNull()]
        [object[]]$States = @()
    )

    $projectId = Get-ObjectPropertyValue -InputObject $Project -Names @("id")
    $workItemId = Get-ObjectPropertyValue -InputObject $WorkItem -Names @("id")
    $githubIssueUrl = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("html_url", "url"))
    $githubState = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("state"))
    $state = Find-PlaneStateForGitHubState -States $States -GitHubState $githubState
    $body = @{
        name = [string](Get-ObjectPropertyValue -InputObject $Issue -Names @("title", "name"))
        description_html = Convert-GitHubBodyToPlaneDescriptionHtml -Body (Get-ObjectPropertyValue -InputObject $Issue -Names @("body")) -GitHubIssueUrl $githubIssueUrl
        external_source = "github"
        external_id = $githubIssueUrl
    }

    if ($null -ne $state) {
        $body.state = Get-ObjectPropertyValue -InputObject $state -Names @("id")
    }

    return Invoke-PlaneApi -Method "Patch" -Config $Config -Token $Token -Path "projects/$projectId/work-items/$workItemId/" -Body $body
}

function Find-GitHubIssueForPlaneWorkItemMarker {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Issues = @(),
        [Parameter(Mandatory)]
        [string]$WorkItemId
    )

    $pattern = '<!--\s*plane-github-sync:.*\bwork_item_id=' + [regex]::Escape($WorkItemId) + '\b'
    foreach ($issue in @($Issues)) {
        $body = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("body"))
        if ($body -match $pattern) {
            return $issue
        }
    }

    return $null
}

function Invoke-PlaneGithubSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $config = Get-PlaneGithubSyncConfig -Path $ConfigPath
    $token = Get-PlaneApiToken -Config $config
    $statePath = Get-PlaneGithubSyncStatePath -Config $config -ConfigPath $ConfigPath
    $state = Get-PlaneGithubSyncState -Path $statePath
    $projects = @(Get-PlaneApiCollection -Config $config -Token $token -Path "projects/")
    $created = @()

    foreach ($mapping in @($config.projectMappings)) {
        $repository = [string](Get-ObjectPropertyValue -InputObject $mapping -Names @("githubRepository", "repository"))
        if ([string]::IsNullOrWhiteSpace($repository)) {
            Write-Warning "Skipping Plane GitHub mapping without githubRepository."
            continue
        }

        $project = Find-PlaneProjectForMapping -Projects $projects -Mapping $mapping
        if ($null -eq $project) {
            $planeProject = Get-ObjectPropertyValue -InputObject $mapping -Names @("planeProject", "planeProjectIdentifier", "planeProjectSlug", "planeProjectName")
            Write-Warning "Plane project '$planeProject' was not found. Skipping $repository."
            continue
        }

        $projectId = Get-ObjectPropertyValue -InputObject $project -Names @("id")
        $workItems = @(Get-PlaneApiCollection -Config $config -Token $token -Path "projects/$projectId/work-items/")
        $states = @(Get-PlaneProjectStates -Config $config -Token $token -Project $project)
        $githubIssues = @(Get-GitHubSyncableIssues -Issues @(Invoke-GitHubIssueList -Repository $repository))
        $githubIssuesByKey = @{}
        $githubIssueUrlsByKey = @{}
        foreach ($issue in $githubIssues) {
            $githubIssueUrl = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("html_url", "url"))
            $githubIssueKey = Get-GitHubIssueIdentityKey -Repository $repository -Url $githubIssueUrl
            if (-not [string]::IsNullOrWhiteSpace($githubIssueKey)) {
                $githubIssuesByKey[$githubIssueKey] = $issue
                $githubIssueUrlsByKey[$githubIssueKey] = $githubIssueUrl
            }
        }

        $linkedWorkItemsByKey = @{}
        $linkedIssueUrlsByKey = @{}
        $linkedKeys = @{}
        $unlinkedWorkItems = @()
        foreach ($workItem in $workItems) {
            if ($null -ne (Get-ObjectPropertyValue -InputObject $workItem -Names @("deleted_at", "archived_at"))) {
                continue
            }

            $githubIssueUrl = Get-PlaneWorkItemGitHubIssueUrl -WorkItem $workItem
            $githubIssueKey = Get-GitHubIssueIdentityKey -Repository $repository -Url $githubIssueUrl
            if (-not [string]::IsNullOrWhiteSpace($githubIssueKey)) {
                $canonicalGitHubIssueUrl = if ($githubIssueUrlsByKey.ContainsKey($githubIssueKey)) { $githubIssueUrlsByKey[$githubIssueKey] } else { $githubIssueUrl }
                $linkedWorkItemsByKey[$githubIssueKey] = $workItem
                $linkedIssueUrlsByKey[$githubIssueKey] = $canonicalGitHubIssueUrl
                $linkedKeys[$githubIssueKey] = $true
                continue
            }

            $linkedFields = @(
                Get-PlaneWorkItemDescription -WorkItem $workItem
                Get-ObjectPropertyValue -InputObject $workItem -Names @("external_id")
            )
            $descriptionIssueKey = ""
            foreach ($field in $linkedFields) {
                $descriptionIssueKey = Get-GitHubIssueIdentityKeyFromText -Repository $repository -Text ([string]$field)
                if (-not [string]::IsNullOrWhiteSpace($descriptionIssueKey)) {
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($descriptionIssueKey) -and $githubIssueUrlsByKey.ContainsKey($descriptionIssueKey)) {
                $linkedWorkItemsByKey[$descriptionIssueKey] = $workItem
                $linkedIssueUrlsByKey[$descriptionIssueKey] = $githubIssueUrlsByKey[$descriptionIssueKey]
                $linkedKeys[$descriptionIssueKey] = $true
                continue
            }

            if (Test-WorkItemLinkedToGitHub -WorkItem $workItem -Repository $repository) {
                foreach ($knownIssueKey in @($githubIssueUrlsByKey.Keys)) {
                    $knownIssueUrl = $githubIssueUrlsByKey[$knownIssueKey]
                    foreach ($field in $linkedFields) {
                        if ([string]$field -match [regex]::Escape($knownIssueUrl)) {
                            $linkedKeys[$knownIssueKey] = $true
                            break
                        }
                    }
                }
                continue
            }

            $unlinkedWorkItems += $workItem
        }

        foreach ($workItem in $unlinkedWorkItems) {
            $workItemId = Get-ObjectPropertyValue -InputObject $workItem -Names @("id")
            $title = Get-PlaneWorkItemTitle -WorkItem $workItem
            $closed = Test-PlaneWorkItemClosed -WorkItem $workItem -States $states
            $existingIssue = Find-GitHubIssueForPlaneWorkItemMarker -Issues $githubIssues -WorkItemId ([string]$workItemId)
            if ($null -ne $existingIssue) {
                $issueUrl = [string](Get-ObjectPropertyValue -InputObject $existingIssue -Names @("html_url", "url"))
                $issueKey = Get-GitHubIssueIdentityKey -Repository $repository -Url $issueUrl
                Update-PlaneWorkItemGitHubLink -Config $config -Token $token -Project $project -WorkItem $workItem -GitHubIssueUrl $issueUrl

                $postLinkDescription = Add-GitHubLinkToPlaneDescription -DescriptionHtml (Get-PlaneWorkItemDescription -WorkItem $workItem) -GitHubIssueUrl $issueUrl
                $planeFingerprint = New-PlaneGithubFingerprint -Title $title -Body (Get-PlainTextFromHtml -Html $postLinkDescription) -Closed $closed
                $githubTitle = [string](Get-ObjectPropertyValue -InputObject $existingIssue -Names @("title", "name"))
                $githubBody = [string](Get-ObjectPropertyValue -InputObject $existingIssue -Names @("body"))
                $githubClosed = ([string](Get-ObjectPropertyValue -InputObject $existingIssue -Names @("state")) -eq "closed")
                $githubFingerprint = New-PlaneGithubFingerprint -Title $githubTitle -Body $githubBody -Closed $githubClosed
                Set-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $issueUrl -Value @{
                    repository = $repository
                    githubIssueUrl = $issueUrl
                    githubIssueNumber = Get-GitHubIssueNumberFromUrl -Url $issueUrl
                    planeProjectId = $projectId
                    planeWorkItemId = $workItemId
                    planeFingerprint = $planeFingerprint
                    githubFingerprint = $githubFingerprint
                }
                if (-not [string]::IsNullOrWhiteSpace($issueKey)) {
                    $linkedKeys[$issueKey] = $true
                }
                continue
            }

            $body = New-PlaneGithubIssueBody -Config $config -Project $project -WorkItem $workItem
            $issueUrl = Invoke-GitHubIssueCreate -Repository $repository -Title $title -Body $body
            Update-PlaneWorkItemGitHubLink -Config $config -Token $token -Project $project -WorkItem $workItem -GitHubIssueUrl $issueUrl

            $postLinkDescription = Add-GitHubLinkToPlaneDescription -DescriptionHtml (Get-PlaneWorkItemDescription -WorkItem $workItem) -GitHubIssueUrl $issueUrl
            $planeFingerprint = New-PlaneGithubFingerprint -Title $title -Body (Get-PlainTextFromHtml -Html $postLinkDescription) -Closed $closed
            $githubFingerprint = New-PlaneGithubFingerprint -Title $title -Body $body -Closed $false
            Set-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $issueUrl -Value @{
                repository = $repository
                githubIssueUrl = $issueUrl
                githubIssueNumber = Get-GitHubIssueNumberFromUrl -Url $issueUrl
                planeProjectId = $projectId
                planeWorkItemId = $workItemId
                planeFingerprint = $planeFingerprint
                githubFingerprint = $githubFingerprint
            }
            $issueKey = Get-GitHubIssueIdentityKey -Repository $repository -Url $issueUrl
            if (-not [string]::IsNullOrWhiteSpace($issueKey)) {
                $linkedKeys[$issueKey] = $true
            }

            $created += [pscustomobject]@{
                Repository = $repository
                Title = $title
                GitHubIssueUrl = $issueUrl
                PlaneWorkItemId = $workItemId
            }
        }

        foreach ($issue in $githubIssues) {
            $githubIssueUrl = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("html_url", "url"))
            $githubIssueKey = Get-GitHubIssueIdentityKey -Repository $repository -Url $githubIssueUrl
            if ([string]::IsNullOrWhiteSpace($githubIssueKey) -or $linkedKeys.ContainsKey($githubIssueKey)) {
                continue
            }

            $newWorkItem = New-PlaneWorkItemFromGitHubIssue -Config $config -Token $token -Project $project -Issue $issue -States $states
            $githubTitle = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("title", "name"))
            $githubBody = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("body"))
            $githubClosed = ([string](Get-ObjectPropertyValue -InputObject $issue -Names @("state")) -eq "closed")
            $planeBody = Get-PlainTextFromHtml -Html (Convert-GitHubBodyToPlaneDescriptionHtml -Body $githubBody -GitHubIssueUrl $githubIssueUrl)
            $planeFingerprint = New-PlaneGithubFingerprint -Title $githubTitle -Body $planeBody -Closed $githubClosed
            $githubFingerprint = New-PlaneGithubFingerprint -Title $githubTitle -Body $githubBody -Closed $githubClosed
            Set-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $githubIssueUrl -Value @{
                repository = $repository
                githubIssueUrl = $githubIssueUrl
                githubIssueNumber = Get-GitHubIssueNumberFromUrl -Url $githubIssueUrl
                planeProjectId = $projectId
                planeWorkItemId = Get-ObjectPropertyValue -InputObject $newWorkItem -Names @("id")
                planeFingerprint = $planeFingerprint
                githubFingerprint = $githubFingerprint
            }
            $linkedKeys[$githubIssueKey] = $true
        }

        foreach ($githubIssueKey in @($linkedWorkItemsByKey.Keys)) {
            if (-not $githubIssuesByKey.ContainsKey($githubIssueKey)) {
                continue
            }

            $workItem = $linkedWorkItemsByKey[$githubIssueKey]
            $issue = $githubIssuesByKey[$githubIssueKey]
            $githubIssueUrl = $githubIssueUrlsByKey[$githubIssueKey]
            $planeLinkedIssueUrl = $linkedIssueUrlsByKey[$githubIssueKey]
            $planeTitle = Get-PlaneWorkItemTitle -WorkItem $workItem
            $planeBody = Get-PlainTextFromHtml -Html (Get-PlaneWorkItemDescription -WorkItem $workItem)
            $planeClosed = Test-PlaneWorkItemClosed -WorkItem $workItem -States $states
            $planeFingerprint = New-PlaneGithubFingerprint -Title $planeTitle -Body $planeBody -Closed $planeClosed
            $githubTitle = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("title", "name"))
            $githubBody = [string](Get-ObjectPropertyValue -InputObject $issue -Names @("body"))
            $githubClosed = ([string](Get-ObjectPropertyValue -InputObject $issue -Names @("state")) -eq "closed")
            $githubFingerprint = New-PlaneGithubFingerprint -Title $githubTitle -Body $githubBody -Closed $githubClosed
            $savedLink = Get-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $githubIssueUrl
            if ($null -eq $savedLink -and $planeLinkedIssueUrl -ne $githubIssueUrl) {
                $savedLink = Get-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $planeLinkedIssueUrl
            }

            if ($null -eq $savedLink) {
                # Missing local state is ambiguous; record a baseline instead of clobbering either side.
            } elseif ($planeFingerprint -eq $savedLink.planeFingerprint -and $githubFingerprint -eq $savedLink.githubFingerprint) {
                # No mutation needed; fall through to refresh the canonical state key.
            } elseif ($planeFingerprint -ne $savedLink.planeFingerprint -and $githubFingerprint -eq $savedLink.githubFingerprint) {
                $githubUpdateBody = Get-GitHubIssueBodyWithSyncMarker -Body $planeBody -ExistingBody $githubBody -Config $config -Project $project -WorkItem $workItem
                Update-GitHubIssueFromPlane -Repository $repository -IssueNumber (Get-GitHubIssueNumberFromUrl -Url $githubIssueUrl) -Title $planeTitle -Body $githubUpdateBody -Closed $planeClosed | Out-Null
                $githubFingerprint = New-PlaneGithubFingerprint -Title $planeTitle -Body $githubUpdateBody -Closed $planeClosed
            } else {
                Update-PlaneWorkItemFromGitHubIssue -Config $config -Token $token -Project $project -WorkItem $workItem -Issue $issue -States $states | Out-Null
                $planeBody = Get-PlainTextFromHtml -Html (Convert-GitHubBodyToPlaneDescriptionHtml -Body $githubBody -GitHubIssueUrl $githubIssueUrl)
                $planeFingerprint = New-PlaneGithubFingerprint -Title $githubTitle -Body $planeBody -Closed $githubClosed
            }

            Set-PlaneGithubSyncStateLink -State $state -Repository $repository -GitHubIssueUrl $githubIssueUrl -Value @{
                repository = $repository
                githubIssueUrl = $githubIssueUrl
                githubIssueNumber = Get-GitHubIssueNumberFromUrl -Url $githubIssueUrl
                planeProjectId = $projectId
                planeWorkItemId = Get-ObjectPropertyValue -InputObject $workItem -Names @("id")
                planeFingerprint = $planeFingerprint
                githubFingerprint = $githubFingerprint
            }
        }
    }

    Save-PlaneGithubSyncState -State $state -Path $statePath
    return $created
}

if ($MyInvocation.InvocationName -ne ".") {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Get-DefaultPlaneGithubSyncConfigPath
    }

    Invoke-PlaneGithubSync -ConfigPath $ConfigPath
}
