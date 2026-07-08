<#
.SYNOPSIS
    Plane Docker Compose self-host setup handler.

.DESCRIPTION
    Downloads Plane's official Community Edition setup script, keeps the local
    plane.env on a low-conflict loopback port, and starts Plane services.
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

function ConvertTo-PlaneBashLiteral {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $singleQuote = [string][char]39
    $escaped = $Value.Replace($singleQuote, "$singleQuote\$singleQuote$singleQuote")
    return "$singleQuote$escaped$singleQuote"
}

function ConvertTo-PlaneBashPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded -match '^(?<drive>[A-Za-z]):[\\/](?<rest>.*)$') {
        $drive = $Matches["drive"].ToLowerInvariant()
        $rest = $Matches["rest"].Replace("\", "/")
        return "/mnt/$drive/$rest"
    }

    return $expanded.Replace("\", "/")
}

function New-PlaneBashProcessArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $bashWorkingDirectory = ConvertTo-PlaneBashPath -Path $WorkingDirectory
    $commandLine = (($Arguments | ForEach-Object { ConvertTo-PlaneBashLiteral -Value $_ }) -join " ")
    $command = "cd $(ConvertTo-PlaneBashLiteral -Value $bashWorkingDirectory) && $commandLine"
    $escapedCommand = $command.Replace('"', '\"')

    return "-lc `"$escapedCommand`""
}

function Update-PlaneSetupScriptCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SetupPath
    )

    if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) {
        return
    }

    $content = Get-Content -LiteralPath $SetupPath -Raw
    $oldBlockPattern = 'if command -v docker-compose &> /dev/null\r?\nthen\r?\n\s+COMPOSE_CMD="docker-compose"\r?\nelse\r?\n\s+COMPOSE_CMD="docker compose"\r?\nfi'
    if ($content -notmatch $oldBlockPattern) {
        return
    }

    $lineEnding = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $newBlock = @(
        'if docker compose version >/dev/null 2>&1'
        'then'
        '    COMPOSE_CMD="docker compose"'
        'elif command -v docker-compose &> /dev/null'
        'then'
        '    COMPOSE_CMD="docker-compose"'
        'else'
        '    COMPOSE_CMD="docker compose"'
        'fi'
    ) -join $lineEnding
    $content = [regex]::Replace($content, $oldBlockPattern, $newBlock, 1)
    [System.IO.File]::WriteAllText($SetupPath, $content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-PlaneBash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BashPath,
        [Parameter(Mandatory)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter()]
        [int]$TimeoutSeconds = 1800
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = New-PlaneBashProcessArgument -WorkingDirectory $WorkingDirectory -Arguments $Arguments
        $process = Start-Process `
            -FilePath $BashPath `
            -ArgumentList $processArguments `
            -WorkingDirectory $WorkingDirectory `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $global:LASTEXITCODE = 124
            return @("Plane setup timed out after $TimeoutSeconds seconds.")
        }

        $global:LASTEXITCODE = $process.ExitCode
        return @(
            Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
        )
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

class PlaneHandler : SetupHandlerBase {
    [int]$DockerCheckTimeoutSeconds = 15
    [int]$SetupTimeoutSeconds = 1800
    [int]$StartTimeoutSeconds = 1800
    [int]$BootstrapTimeoutSeconds = 300
    [int]$HttpPort = 18080
    [int]$HttpsPort = 18081
    [string]$WorkspaceName = "Ruru"
    [string]$WorkspaceSlug = "ruru"
    [string]$OpAccount = "my.1password.com"
    [string]$OpVault = "hxgiw3ekjzktxf7hiyf5lyb4hi"
    [string]$OpItem = "fzhjphxau3ila6wlelo5y4ehhe"
    [string]$AdminEmailRef = "op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/username"
    [string]$AdminPasswordRef = "op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/password"
    [string]$ApiTokenRef = "op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/credential"
    [string]$SetupScriptUrl = "https://github.com/makeplane/plane/releases/latest/download/setup.sh"

    PlaneHandler() {
        $this.Name = "Plane"
        $this.Description = "Plane Docker Compose セットアップ"
        $this.Order = 57
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($this.IsSkipped($ctx)) {
            $this.Log("Plane セットアップはオプションで無効化されています", "Gray")
            return $false
        }

        if (-not (Get-Command -Name "docker" -ErrorAction SilentlyContinue)) {
            $this.Log("docker コマンドが見つかりません", "Gray")
            return $false
        }

        if (-not (Get-Command -Name "bash" -ErrorAction SilentlyContinue)) {
            $this.Log("bash コマンドが見つかりません", "Gray")
            return $false
        }

        if (-not (Test-DockerDaemon -TimeoutSeconds $this.DockerCheckTimeoutSeconds)) {
            $this.Log("Docker daemon が応答しないため Plane をスキップします", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $this.ConfigureFromOptions($ctx)

            $selfhostDir = $this.GetSelfhostDir($ctx)
            $appDir = Join-Path $selfhostDir "plane-app"
            $envPath = Join-Path $appDir "plane.env"
            $setupPath = Join-Path $selfhostDir "setup.sh"
            $bashPath = $this.GetBashPath()

            if ([string]::IsNullOrWhiteSpace($bashPath)) {
                return $this.CreateFailureResult("bash コマンドが見つかりません")
            }

            $this.EnsureDirectory($selfhostDir)
            $this.EnsureSetupScript($setupPath)

            if (-not $this.TestPlaneInstalled($appDir)) {
                $installOutput = @(Invoke-PlaneBash -BashPath $bashPath -WorkingDirectory $selfhostDir -Arguments @("./setup.sh", "install") -TimeoutSeconds $this.SetupTimeoutSeconds)
                if ($LASTEXITCODE -ne 0) {
                    return $this.CreateFailureResult("Plane setup.sh install に失敗しました: $(($installOutput -join "`n").Trim())")
                }
            }

            $this.EnsureDirectory($appDir)
            $this.EnsurePlaneEnvironment($envPath)

            $startOutput = @(Invoke-PlaneBash -BashPath $bashPath -WorkingDirectory $selfhostDir -Arguments @("./setup.sh", "start") -TimeoutSeconds $this.StartTimeoutSeconds)
            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("Plane setup.sh start に失敗しました: $(($startOutput -join "`n").Trim())")
            }

            $this.EnsurePlaneBootstrap($ctx, $selfhostDir, $bashPath)

            $url = $this.GetPlaneUrl()
            $this.Log("Plane を起動しました: $url", "Green")
            return $this.CreateSuccessResult("Plane を起動しました: $url")
        }
        catch {
            return $this.CreateFailureResult("Plane セットアップに失敗しました: $($_.Exception.Message)", $_.Exception)
        }
    }

    hidden [void] ConfigureFromOptions([SetupContext]$ctx) {
        $this.HttpPort = $this.GetIntOption($ctx, "PlaneHttpPort", $this.HttpPort)
        $this.HttpsPort = $this.GetIntOption($ctx, "PlaneHttpsPort", $this.HttpsPort)
        $this.SetupTimeoutSeconds = $this.GetIntOption($ctx, "PlaneSetupTimeoutSeconds", $this.SetupTimeoutSeconds)
        $this.StartTimeoutSeconds = $this.GetIntOption($ctx, "PlaneStartTimeoutSeconds", $this.StartTimeoutSeconds)
        $this.BootstrapTimeoutSeconds = $this.GetIntOption($ctx, "PlaneBootstrapTimeoutSeconds", $this.BootstrapTimeoutSeconds)
        $this.WorkspaceName = $this.GetStringOption($ctx, "PlaneWorkspaceName", $this.WorkspaceName)
        $this.WorkspaceSlug = $this.GetStringOption($ctx, "PlaneWorkspaceSlug", $this.WorkspaceSlug)
        $this.OpAccount = $this.GetStringOption($ctx, "PlaneOpAccount", $this.OpAccount)
        $this.OpVault = $this.GetStringOption($ctx, "PlaneOpVault", $this.OpVault)
        $this.OpItem = $this.GetStringOption($ctx, "PlaneOpItem", $this.OpItem)
        $this.AdminEmailRef = $this.GetStringOption($ctx, "PlaneAdminEmailRef", $this.AdminEmailRef)
        $this.AdminPasswordRef = $this.GetStringOption($ctx, "PlaneAdminPasswordRef", $this.AdminPasswordRef)
        $this.ApiTokenRef = $this.GetStringOption($ctx, "PlaneApiTokenRef", $this.ApiTokenRef)
    }

    hidden [bool] IsSkipped([SetupContext]$ctx) {
        if ($this.IsTruthy($ctx.GetOption("SkipPlane", $false))) {
            return $true
        }

        return -not $this.IsTruthy($ctx.GetOption("PlaneEnabled", $true))
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }
        if ($value -is [int]) { return [int]$value -ne 0 }
        $text = ([string]$value).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return $false }
        return $text -in @("1", "true", "yes", "y", "on", "enabled")
    }

    hidden [int] GetIntOption([SetupContext]$ctx, [string]$key, [int]$defaultValue) {
        $raw = $ctx.GetOption($key, $defaultValue)
        $parsed = 0
        if ([int]::TryParse([string]$raw, [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }
        return $defaultValue
    }

    hidden [string] GetStringOption([SetupContext]$ctx, [string]$key, [string]$defaultValue) {
        $raw = [string]$ctx.GetOption($key, $defaultValue)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaultValue
        }
        return $raw.Trim()
    }

    hidden [string] GetSelfhostDir([SetupContext]$ctx) {
        $configured = [string]$ctx.GetOption("PlaneSelfhostDir", "")
        if (-not [string]::IsNullOrWhiteSpace($configured)) {
            return [Environment]::ExpandEnvironmentVariables($configured)
        }

        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "~" }
        return Join-Path $homeDir "plane-selfhost"
    }

    hidden [string] GetBashPath() {
        $bash = Get-Command -Name "bash" -ErrorAction SilentlyContinue
        if ($null -eq $bash) { return "" }
        if ($bash.Source) { return [string]$bash.Source }
        return [string]$bash.Path
    }

    hidden [void] EnsureDirectory([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    hidden [void] EnsureSetupScript([string]$setupPath) {
        if (Test-Path -LiteralPath $setupPath -PathType Leaf) {
            Update-PlaneSetupScriptCompatibility -SetupPath $setupPath
            return
        }

        $this.Log("Plane setup.sh をダウンロードしています...")
        Invoke-WebRequestSafe -Uri $this.SetupScriptUrl -OutFile $setupPath
        Update-PlaneSetupScriptCompatibility -SetupPath $setupPath
    }

    hidden [bool] TestPlaneInstalled([string]$appDir) {
        $envPath = Join-Path $appDir "plane.env"
        $composePath = Join-Path $appDir "docker-compose.yaml"
        return (Test-Path -LiteralPath $envPath -PathType Leaf) -and
            (Test-Path -LiteralPath $composePath -PathType Leaf)
    }

    hidden [void] EnsurePlaneEnvironment([string]$envPath) {
        $parent = Split-Path -Parent $envPath
        $this.EnsureDirectory($parent)

        $lines = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $envPath -PathType Leaf) {
            foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
                $lines.Add($line)
            }
        }

        $this.SetEnvValue($lines, "LISTEN_HTTP_PORT", [string]$this.HttpPort)
        $this.SetEnvValue($lines, "LISTEN_HTTPS_PORT", [string]$this.HttpsPort)
        $this.SetEnvValue($lines, "WEB_URL", $this.GetPlaneUrl())
        $this.SetEnvValue($lines, "CORS_ALLOWED_ORIGINS", $this.GetPlaneUrl())

        $content = ($lines -join "`n") + "`n"
        [System.IO.File]::WriteAllText($envPath, $content, [System.Text.UTF8Encoding]::new($false))
    }

    hidden [void] SetEnvValue([System.Collections.Generic.List[string]]$lines, [string]$key, [string]$value) {
        $pattern = "^{0}=" -f [regex]::Escape($key)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pattern) {
                $lines[$i] = "$key=$value"
                return
            }
        }
        $lines.Add("$key=$value")
    }

    hidden [string] GetPlaneUrl() {
        return "http://127.0.0.1:$($this.HttpPort)"
    }

    hidden [void] EnsurePlaneBootstrap([SetupContext]$ctx, [string]$selfhostDir, [string]$bashPath) {
        $config = $this.ResolvePlaneBootstrapConfig($ctx)
        if ($null -eq $config) {
            $this.Log("Plane bootstrap credential が未設定のため初期 workspace seed をスキップします", "Gray")
            return
        }

        $payloadPath = Join-Path $selfhostDir "plane-bootstrap-payload.json"
        $scriptPath = Join-Path $selfhostDir "plane-bootstrap.py"
        try {
            $payload = [ordered]@{
                email          = $config.Email
                password       = $config.Password
                api_token      = $config.ApiToken
                workspace_name = $this.WorkspaceName
                workspace_slug = $this.WorkspaceSlug
                plane_url      = $this.GetPlaneUrl()
            } | ConvertTo-Json -Compress

            [System.IO.File]::WriteAllText($payloadPath, $payload, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($scriptPath, $this.NewPlaneBootstrapScript(), [System.Text.UTF8Encoding]::new($false))

            $payloadBashPath = ConvertTo-PlaneBashPath -Path $payloadPath
            $scriptBashPath = ConvertTo-PlaneBashPath -Path $scriptPath
            $this.InvokePlaneBashStep($bashPath, $selfhostDir, @("docker", "cp", $payloadBashPath, "plane-app-api-1:/tmp/plane_bootstrap_payload.json"), "Plane bootstrap payload copy")
            $this.InvokePlaneBashStep($bashPath, $selfhostDir, @("docker", "cp", $scriptBashPath, "plane-app-api-1:/tmp/plane_bootstrap.py"), "Plane bootstrap script copy")
            $this.InvokePlaneBashStep(
                $bashPath,
                $selfhostDir,
                @("docker", "exec", "plane-app-api-1", "sh", "-lc", "python3 manage.py shell < /tmp/plane_bootstrap.py && rm -f /tmp/plane_bootstrap.py /tmp/plane_bootstrap_payload.json"),
                "Plane bootstrap"
            )
        }
        finally {
            Remove-Item -LiteralPath $payloadPath, $scriptPath -Force -ErrorAction SilentlyContinue
        }
    }

    hidden [pscustomobject] ResolvePlaneBootstrapConfig([SetupContext]$ctx) {
        $email = $this.GetStringOption($ctx, "PlaneAdminEmail", "")
        $password = $this.GetStringOption($ctx, "PlaneAdminPassword", "")
        $apiToken = $this.GetStringOption($ctx, "PlaneApiToken", "")

        $opAvailable = $null -ne (Get-Command -Name "op" -ErrorAction SilentlyContinue)
        if ($opAvailable) {
            if ([string]::IsNullOrWhiteSpace($email)) {
                $email = $this.ReadPlaneSecret($this.AdminEmailRef, $false)
            }
            if ([string]::IsNullOrWhiteSpace($password)) {
                $password = $this.ReadPlaneSecret($this.AdminPasswordRef, $false)
            }
            if ([string]::IsNullOrWhiteSpace($apiToken)) {
                $apiToken = $this.ReadPlaneSecret($this.ApiTokenRef, $false)
            }
        }

        if ([string]::IsNullOrWhiteSpace($email) -or [string]::IsNullOrWhiteSpace($password)) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($apiToken)) {
            $apiToken = $this.NewPlaneApiToken()
            if ($opAvailable) {
                $this.SetPlaneCredentialSecret($apiToken)
            }
        }

        return [pscustomobject]@{
            Email    = $email.Trim().ToLowerInvariant()
            Password = $password
            ApiToken = $apiToken
        }
    }

    hidden [string] ReadPlaneSecret([string]$ref, [bool]$required) {
        if ([string]::IsNullOrWhiteSpace($ref)) {
            if ($required) { throw "Plane 1Password ref が未設定です" }
            return ""
        }

        $output = & op --cache=false read --account $this.OpAccount $ref 2>$null
        if ($LASTEXITCODE -ne 0) {
            if ($required) { throw "1Password から Plane secret を取得できません: $ref" }
            return ""
        }

        return (($output -join "`n").Trim())
    }

    hidden [void] SetPlaneCredentialSecret([string]$apiToken) {
        $itemJson = & op --cache=false item get $this.OpItem --vault $this.OpVault --account $this.OpAccount --format json
        if ($LASTEXITCODE -ne 0) {
            throw "Plane API token 保存先の 1Password item を取得できません"
        }

        $item = ($itemJson -join "`n") | ConvertFrom-Json
        $fields = [System.Collections.ArrayList]::new()
        foreach ($field in @($item.fields)) {
            [void]$fields.Add($field)
        }

        $credential = $fields | Where-Object { $_.label -eq "credential" } | Select-Object -First 1
        if ($null -eq $credential) {
            [void]$fields.Add([pscustomobject]@{
                    id      = "credential"
                    type    = "CONCEALED"
                    purpose = $null
                    label   = "credential"
                    value   = $apiToken
                })
        }
        else {
            $credential.type = "CONCEALED"
            $credential.value = $apiToken
        }

        $item.fields = @($fields)
        $payload = $item | ConvertTo-Json -Depth 100
        $payload | & op --cache=false item edit $this.OpItem --vault $this.OpVault --account $this.OpAccount | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Plane API token を 1Password item に保存できません"
        }
    }

    hidden [string] NewPlaneApiToken() {
        return "plane_api_$([guid]::NewGuid().ToString("N"))"
    }

    hidden [void] InvokePlaneBashStep([string]$bashPath, [string]$workingDirectory, [string[]]$arguments, [string]$stepName) {
        $output = @(Invoke-PlaneBash -BashPath $bashPath -WorkingDirectory $workingDirectory -Arguments $arguments -TimeoutSeconds $this.BootstrapTimeoutSeconds)
        if ($LASTEXITCODE -ne 0) {
            throw "$stepName に失敗しました: $(($output -join "`n").Trim())"
        }
    }

    hidden [string] NewPlaneBootstrapScript() {
        return @'
import json
from django.db import transaction
from plane.db.models import (
    APIToken,
    DEFAULT_STATES,
    Issue,
    Profile,
    Project,
    ProjectIdentifier,
    ProjectMember,
    State,
    User,
    Workspace,
    WorkspaceMember,
)
from plane.license.models import Instance, InstanceAdmin

PROJECT_SEEDS = [
    {"name": "dotfiles", "identifier": "DOTFILES", "description": "dotfiles repository tasks"},
    {"name": "article-collector", "identifier": "ARTICLE", "description": "article-collector repository tasks"},
    {"name": "lifelog", "identifier": "LIFELOG", "description": "lifelog repository tasks"},
]

with open("/tmp/plane_bootstrap_payload.json", "r") as fh:
    payload = json.load(fh)

email = payload["email"].strip().lower()
password = payload["password"]
api_token = payload["api_token"]
workspace_name = payload["workspace_name"]
workspace_slug = payload["workspace_slug"]
plane_url = payload["plane_url"]


def remove_placeholder_project(workspace):
    placeholder_identifier = workspace_slug.replace("-", "")[:12].upper()
    Project.objects.filter(
        workspace=workspace,
        name=workspace_name,
        identifier=placeholder_identifier,
    ).delete()
    Issue.issue_objects.filter(
        workspace=workspace,
        project__deleted_at__isnull=False,
    ).delete()


def ensure_project(workspace, user, seed):
    project = Project.objects.filter(workspace=workspace, name=seed["name"]).first()
    if project is None:
        project = Project.objects.filter(workspace=workspace, identifier=seed["identifier"]).first()

    if project is None:
        project = Project.objects.create(
            workspace=workspace,
            name=seed["name"],
            identifier=seed["identifier"],
            description=seed["description"],
            project_lead=user,
            network=2,
            module_view=True,
            cycle_view=True,
            issue_views_view=True,
            page_view=True,
            intake_view=True,
        )
    else:
        project.name = seed["name"]
        project.identifier = seed["identifier"]
        project.description = seed["description"]
        project.project_lead = user
        project.module_view = True
        project.cycle_view = True
        project.issue_views_view = True
        project.page_view = True
        project.intake_view = True
        project.save()

    ProjectIdentifier.objects.update_or_create(
        project=project,
        defaults={"workspace": workspace, "name": project.identifier},
    )
    ProjectMember.objects.update_or_create(
        project=project,
        member=user,
        defaults={"workspace": workspace, "role": 20, "is_active": True},
    )

    for state in DEFAULT_STATES:
        State.all_state_objects.update_or_create(
            project=project,
            name=state["name"],
            defaults={
                "workspace": workspace,
                "color": state["color"],
                "sequence": state["sequence"],
                "group": state["group"],
                "default": state.get("default", False),
                "created_by": user,
            },
        )

    return project

with transaction.atomic():
    user = User.objects.filter(email=email).first()
    if user is None:
        username = email
        suffix = 1
        while User.objects.filter(username=username).exists():
            suffix += 1
            username = f"{email}-{suffix}"
        user = User(username=username, email=email)

    user.set_password(password)
    user.is_active = True
    user.is_email_verified = True
    user.is_staff = True
    user.is_superuser = True
    user.is_password_autoset = False
    user.is_password_reset_required = False
    user.save()

    profile, _ = Profile.objects.get_or_create(user=user)
    profile.is_onboarded = True
    profile.is_tour_completed = True
    profile.onboarding_step = {
        "profile_complete": True,
        "workspace_create": True,
        "workspace_invite": True,
        "workspace_join": True,
    }
    profile.company_name = workspace_name
    profile.role = profile.role or "Owner"
    profile.use_case = profile.use_case or "Project management"

    workspace, created_workspace = Workspace.objects.get_or_create(
        slug=workspace_slug,
        defaults={
            "name": workspace_name,
            "owner": user,
            "organization_size": "1-10",
            "timezone": "Asia/Tokyo",
        },
    )
    workspace.owner = user
    workspace.name = workspace_name
    workspace.organization_size = workspace.organization_size or "1-10"
    workspace.timezone = "Asia/Tokyo"
    workspace.save()

    WorkspaceMember.objects.update_or_create(
        workspace=workspace,
        member=user,
        defaults={"role": 20, "company_role": "Owner", "is_active": True},
    )

    profile.last_workspace_id = workspace.id
    profile.save()

    instance = Instance.objects.first()
    if instance is not None:
        instance.is_setup_done = True
        instance.is_signup_screen_visited = True
        instance.is_verified = True
        instance.domain = instance.domain or plane_url
        instance.instance_name = instance.instance_name or f"{workspace_name} Plane"
        instance.save()
        InstanceAdmin.objects.update_or_create(
            instance=instance,
            user=user,
            defaults={"role": 20, "is_verified": True},
        )

    APIToken.objects.update_or_create(
        label="codex-plane-mcp",
        user=user,
        defaults={
            "description": "Local Plane MCP and GitHub sync token managed by dotfiles bootstrap.",
            "token": api_token,
            "workspace": workspace,
            "is_active": True,
            "is_service": False,
            "user_type": 0,
            "expired_at": None,
            "allowed_rate_limit": "600/min",
        },
    )

remove_placeholder_project(workspace)
for seed in PROJECT_SEEDS:
    ensure_project(workspace, user, seed)
'@
    }
}
