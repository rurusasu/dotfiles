Describe "Hermes bootstrap type loading" {
    It "loads error-history support when an older drain type already exists in the session" {
        $sourcePath = (Resolve-Path (Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1")).ProviderPath
        $escapedSourcePath = $sourcePath.Replace("'", "''")
        $childScript = @"
Add-Type -TypeDefinition @'
public sealed class HermesBootstrapBoundedDrain { }
'@
if ("HermesBootstrapErrorHistory" -as [type]) { exit 40 }
. '$escapedSourcePath'
if (-not ("HermesBootstrapErrorHistory" -as [type])) { exit 41 }
`$history = [System.Collections.ArrayList]::new()
`$record = [System.Management.Automation.ErrorRecord]::new(
    [System.InvalidOperationException]::new("baseline"),
    "HermesBootstrapTypeLoadingTest",
    [System.Management.Automation.ErrorCategory]::NotSpecified,
    `$null
)
[void]`$history.Add(`$record)
[HermesBootstrapErrorHistory]::Restore(`$history, @(`$record))
if (`$history.Count -ne 1 -or -not [object]::ReferenceEquals(`$history[0], `$record)) { exit 42 }
exit 0
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $pwshPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

        $output = @(& $pwshPath -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
}

Describe "Get-HermesBootstrapSecretPlan" {
    BeforeAll {
        $sourcePath = Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1"
        if (Test-Path -LiteralPath $sourcePath) {
            . $sourcePath
        }
    }

    BeforeEach {
        $script:dockerArguments = @()
        $script:dockerExitCode = 0
        $script:dockerOutput = @(
            '{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]}]}'
        )
        function global:Invoke-Docker {
            param([string[]]$Arguments)

            $script:dockerArguments = @($Arguments)
            $global:LASTEXITCODE = $script:dockerExitCode
            return $script:dockerOutput
        }
    }

    It "requests the non-secret plan with the exact Docker Compose argument array" {
        $plan = Get-HermesBootstrapSecretPlan -ComposeFile "C:\dotfiles\docker\hermes-agent\compose.yml"

        $script:dockerArguments | Should -Be @(
            "compose", "-f", "C:\dotfiles\docker\hermes-agent\compose.yml",
            "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "secret-plan"
        )
        $plan.schema_version | Should -Be 1
        @($plan.items).Count | Should -Be 6
    }

    It "rejects plans that replace an allowlisted 1Password reference" {
        $validJson = $script:dockerOutput[0]
        $mutations = @(
            @{ Index = 0; Property = "account"; Value = "attacker.1password.com" },
            @{ Index = 1; Property = "vault"; Value = "private" },
            @{ Index = 2; Property = "item"; Value = "Arbitrary Secret" },
            @{ Index = 3; Property = "key"; Value = "arbitrary" }
        )

        foreach ($mutation in $mutations) {
            $invalidPlan = $validJson | ConvertFrom-Json -Depth 32
            $invalidPlan.items[$mutation.Index].($mutation.Property) = $mutation.Value
            $script:dockerOutput = @($invalidPlan | ConvertTo-Json -Compress -Depth 32)

            { Get-HermesBootstrapSecretPlan -ComposeFile "compose.yml" } |
                Should -Throw -ExpectedMessage "Hermes bootstrap secret plan is invalid."
        }
    }

    It "rejects a reordered allowlisted 1Password plan" {
        $invalidPlan = $script:dockerOutput[0] | ConvertFrom-Json -Depth 32
        $items = @($invalidPlan.items)
        $invalidPlan.items = @($items[1], $items[0]) + $items[2..5]
        $script:dockerOutput = @($invalidPlan | ConvertTo-Json -Compress -Depth 32)

        { Get-HermesBootstrapSecretPlan -ComposeFile "compose.yml" } |
            Should -Throw -ExpectedMessage "Hermes bootstrap secret plan is invalid."
    }

    It "rejects plans that do not satisfy the exact six-item metadata schema" {
        $validPlan = ($script:dockerOutput -join "`n") | ConvertFrom-Json -Depth 32
        $invalidPlans = @()

        $wrongSchema = $validPlan.PSObject.Copy()
        $wrongSchema.schema_version = 2
        $invalidPlans += $wrongSchema

        $stringSchema = $validPlan.PSObject.Copy()
        $stringSchema.schema_version = "1"
        $invalidPlans += $stringSchema

        $booleanSchema = $validPlan.PSObject.Copy()
        $booleanSchema.schema_version = $true
        $invalidPlans += $booleanSchema

        $wrongCount = $validPlan.PSObject.Copy()
        $wrongCount.items = @($validPlan.items)[0..4]
        $invalidPlans += $wrongCount

        $duplicateKey = $validPlan.PSObject.Copy()
        $duplicateKey.items = @($validPlan.items | ForEach-Object { $_.PSObject.Copy() })
        $duplicateKey.items[1].key = $duplicateKey.items[0].key
        $invalidPlans += $duplicateKey

        $blankVault = $validPlan.PSObject.Copy()
        $blankVault.items = @($validPlan.items | ForEach-Object { $_.PSObject.Copy() })
        $blankVault.items[0].vault = " "
        $invalidPlans += $blankVault

        $paddedItem = $validPlan.PSObject.Copy()
        $paddedItem.items = @($validPlan.items | ForEach-Object { $_.PSObject.Copy() })
        $paddedItem.items[0].item = " Hermes Agent Dashboard"
        $invalidPlans += $paddedItem

        $extraPlanProperty = $validPlan.PSObject.Copy()
        $extraPlanProperty | Add-Member -NotePropertyName unexpected -NotePropertyValue "no"
        $invalidPlans += $extraPlanProperty

        $invalidField = $validPlan.PSObject.Copy()
        $invalidField.items = @($validPlan.items | ForEach-Object { $_.PSObject.Copy() })
        $invalidField.items[0].fields = @([PSCustomObject]@{ canonical_name = ""; labels = @("username") })
        $invalidPlans += $invalidField

        $paddedField = $validPlan.PSObject.Copy()
        $paddedField.items = @($validPlan.items | ForEach-Object { $_.PSObject.Copy() })
        $paddedField.items[0].fields = @([PSCustomObject]@{ canonical_name = "username"; labels = @(" username") })
        $invalidPlans += $paddedField

        foreach ($invalidPlan in $invalidPlans) {
            $script:dockerOutput = @($invalidPlan | ConvertTo-Json -Compress -Depth 32)

            { Get-HermesBootstrapSecretPlan -ComposeFile "compose.yml" } |
                Should -Throw -ExpectedMessage "Hermes bootstrap secret plan is invalid."
        }
    }

    It "rejects a trailing second JSON document or trailing garbage" {
        $validJson = $script:dockerOutput[0]
        foreach ($suffix in @("`n$validJson", " trailing-garbage")) {
            $script:dockerOutput = @("$validJson$suffix")

            { Get-HermesBootstrapSecretPlan -ComposeFile "compose.yml" } |
                Should -Throw -ExpectedMessage "Hermes bootstrap secret plan is invalid."
        }
    }
}

function global:New-HermesBootstrapFakeDocker {
    param([Parameter(Mandatory)][string]$Directory)

    if ($IsWindows) {
        $path = Join-Path $Directory "docker.cmd"
        @'
@echo off
setlocal
set args=%HERMES_BOOTSTRAP_TEST_DIR%\arguments.txt
set input=%HERMES_BOOTSTRAP_TEST_DIR%\stdin.txt
> "%args%" (
  for %%A in (%*) do echo %%~A
)
more > "%input%"
if "%HERMES_BOOTSTRAP_TEST_HANG%"=="1" ping 127.0.0.1 -n 3 >nul
if "%HERMES_BOOTSTRAP_TEST_LARGE_OUTPUT%"=="1" pwsh -NoLogo -NoProfile -NonInteractive -Command "$text = '0123456789abcdef' * 131072; [Console]::Out.Write($text); [Console]::Error.Write($text)"
if not "%HERMES_BOOTSTRAP_TEST_STDOUT%"=="" pwsh -NoLogo -NoProfile -NonInteractive -Command "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); [Console]::Out.Write($env:HERMES_BOOTSTRAP_TEST_STDOUT)"
if not "%HERMES_BOOTSTRAP_TEST_STDERR%"=="" pwsh -NoLogo -NoProfile -NonInteractive -Command "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); [Console]::Error.Write($env:HERMES_BOOTSTRAP_TEST_STDERR)"
exit /b %HERMES_BOOTSTRAP_TEST_EXIT%
'@ | Set-Content -LiteralPath $path -NoNewline
        return $path
    }

    $path = Join-Path $Directory "docker"
    $content = @'
#!/bin/sh
printf '%s' "$$" > "$HERMES_BOOTSTRAP_TEST_DIR/pid"
printf '%s\0' "$@" > "$HERMES_BOOTSTRAP_TEST_DIR/arguments.bin"
cat > "$HERMES_BOOTSTRAP_TEST_DIR/stdin.txt"
if [ "${HERMES_BOOTSTRAP_TEST_HANG:-0}" = "1" ]; then
  sleep 2 &
  printf '%s' "$!" > "$HERMES_BOOTSTRAP_TEST_DIR/descendant-pid"
  wait "$!"
fi
if [ "${HERMES_BOOTSTRAP_TEST_LARGE_OUTPUT:-0}" = "1" ]; then
  yes stdout | head -c 2097152
  yes stderr | head -c 2097152 >&2
fi
printf '%s' "${HERMES_BOOTSTRAP_TEST_STDOUT:-}"
printf '%s' "${HERMES_BOOTSTRAP_TEST_STDERR:-}" >&2
exit "${HERMES_BOOTSTRAP_TEST_EXIT:-0}"
'@
    $content.Replace("`r`n", "`n") | Set-Content -LiteralPath $path -NoNewline
    & chmod +x $path
    return $path
}

function global:Test-HermesBootstrapErrorGraphMarker {
    param(
        [object[]]$Roots,
        [Parameter(Mandatory)][string]$Marker
    )

    $pending = [System.Collections.Generic.Stack[object]]::new()
    foreach ($root in @($Roots)) {
        if ($null -ne $root) { $pending.Push($root) }
    }
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    while ($pending.Count -gt 0) {
        $value = $pending.Pop()
        if ($null -eq $value) { continue }
        if ($value -is [string]) {
            if ($value.Contains($Marker, [StringComparison]::Ordinal)) { return $true }
            continue
        }

        $identity = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($value)
        if (-not $visited.Add($identity)) { continue }
        if ($value -is [System.Management.Automation.ErrorRecord]) {
            foreach ($child in @(
                    $value.Exception, $value.ErrorDetails, $value.InvocationInfo,
                    $value.ScriptStackTrace, $value.TargetObject
                )) {
                if ($null -ne $child) { $pending.Push($child) }
            }
            continue
        }
        if ($value -is [System.Exception]) {
            foreach ($child in @($value.Message, $value.StackTrace, $value.InnerException, $value.Data)) {
                if ($null -ne $child) { $pending.Push($child) }
            }
            continue
        }
        if ($value -is [System.Management.Automation.InvocationInfo]) {
            foreach ($child in @($value.Line, $value.PositionMessage, $value.InvocationName)) {
                if ($null -ne $child) { $pending.Push($child) }
            }
            continue
        }
        if ($value -is [System.Collections.IDictionary]) {
            foreach ($key in $value.Keys) {
                $pending.Push($key)
                $pending.Push($value[$key])
            }
        }
    }
    return $false
}

function global:Restore-HermesBootstrapTestErrorHistory {
    param(
        [AllowEmptyCollection()]
        [System.Management.Automation.ErrorRecord[]]$Snapshot
    )

    $global:Error.Clear()
    foreach ($errorRecord in @($Snapshot)) {
        [void]$global:Error.Add($errorRecord)
    }
}

function global:New-HermesBootstrapTestErrorRecord {
    param([Parameter(Mandatory)][string]$Message)

    return [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($Message),
        "HermesBootstrapTestBaseline",
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $null
    )
}

Describe "Invoke-HermesBootstrap" {
    BeforeAll {
        $sourcePath = Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1"
        if (Test-Path -LiteralPath $sourcePath) {
            . $sourcePath
        }
    }

    BeforeEach {
        $script:dockerOutput = @(
            '{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["bot_token"]}]}]}'
        )
        function global:Invoke-Docker {
            param([string[]]$Arguments)

            [void]$Arguments
            $global:LASTEXITCODE = 0
            return $script:dockerOutput
        }

        $script:originalPath = $env:PATH
        $script:fakeDockerDirectory = Join-Path $TestDrive "bin"
        New-Item -ItemType Directory -Path $script:fakeDockerDirectory -Force | Out-Null
        $fakeDockerPath = New-HermesBootstrapFakeDocker -Directory $script:fakeDockerDirectory
        $script:dockerProcessParameters = if ($IsWindows) {
            @{
                DockerExecutable      = $env:ComSpec
                DockerPrefixArguments = @("/d", "/c", $fakeDockerPath)
            }
        }
        else {
            @{
                DockerExecutable      = $fakeDockerPath
                DockerPrefixArguments = @()
            }
        }
        $env:PATH = "$script:fakeDockerDirectory$([IO.Path]::PathSeparator)$script:originalPath"
        $env:HERMES_BOOTSTRAP_TEST_DIR = $TestDrive
        $env:HERMES_BOOTSTRAP_TEST_EXIT = "0"
        $env:HERMES_BOOTSTRAP_TEST_STDOUT = "bootstrap complete"
        $env:HERMES_BOOTSTRAP_TEST_STDERR = ""
        $env:HERMES_BOOTSTRAP_TEST_LARGE_OUTPUT = "0"
        $env:HERMES_BOOTSTRAP_TEST_HANG = "0"
        $script:HermesBootstrapProcessTimeoutMilliseconds = 30 * 60 * 1000
        $script:HermesBootstrapTerminationTimeoutMilliseconds = 5000
        $script:HermesBootstrapDrainTimeoutMilliseconds = 5000
        $script:onePasswordCalls = [System.Collections.Generic.List[string]]::new()
    }

    AfterEach {
        $env:PATH = $script:originalPath
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_EXIT -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_STDOUT -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_STDERR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_LARGE_OUTPUT -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BOOTSTRAP_TEST_HANG -ErrorAction SilentlyContinue
    }

    It "streams compact header, declared item records, and end directly to Docker stdin" {
        $secret = "not-an-argument-secret"
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:onePasswordCalls.Add(($Arguments -join "|")) | Out-Null
            $itemName = $Arguments[2]
            return @{ id = "id-$itemName"; fields = @(@{ label = "username"; value = $secret }) } | ConvertTo-Json -Compress
        }

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

        $result.Success | Should -BeTrue
        $result.Changed | Should -BeTrue
        $result.Message | Should -Be "Hermes bootstrap completed."
        $global:LASTEXITCODE | Should -Be 0
        $script:onePasswordCalls | Should -Be @(
            "item|get|Hermes Agent Dashboard|--account|my.1password.com|--vault|openclaw|--format|json",
            "item|get|GitHubUsedOpenClawPAT|--account|my.1password.com|--vault|openclaw|--format|json",
            "item|get|SlackBot-OpenClaw|--account|my.1password.com|--vault|openclaw|--format|json",
            "item|get|SlackBot-Rick|--account|my.1password.com|--vault|openclaw|--format|json",
            "item|get|SlackBot-Hoffman|--account|my.1password.com|--vault|openclaw|--format|json",
            "item|get|SlackBot-Risarisa|--account|my.1password.com|--vault|openclaw|--format|json"
        )

        $records = (Get-Content -LiteralPath (Join-Path $TestDrive "stdin.txt") -Raw -Encoding utf8) -split "\r?\n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 32 }
        @($records).Count | Should -Be 8
        $records[0].type | Should -Be "header"
        $records[0].schema_version | Should -Be 1
        @($records[1..6] | ForEach-Object { $_.key }) | Should -Be @(
            "dashboard", "github", "slack_default", "slack_rick", "slack_hoffman", "slack_risarisa"
        )
        $records[7].type | Should -Be "end"

        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1") -Raw
        $source | Should -Match "ArgumentList\.Add"
        $source | Should -Not -Match "New-TemporaryFile|GetTempFileName|Set-Content|Out-File"
        $arguments = if ($IsWindows) {
            Get-Content -LiteralPath (Join-Path $TestDrive "arguments.txt") -Raw
        }
        else {
            [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $TestDrive "arguments.bin")))
        }
        $arguments | Should -Not -Match ([regex]::Escape($secret))
        $arguments | Should -Not -Match "--reveal"
        $argumentList = if ($IsWindows) {
            @(Get-Content -LiteralPath (Join-Path $TestDrive "arguments.txt"))
        }
        else {
            @($arguments -split "`0" | Where-Object { $_.Length -gt 0 })
        }
        $argumentList | Should -Be @(
            "compose", "-f", "compose.yml",
            "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "apply"
        )
        $rawLines = @((Get-Content -LiteralPath (Join-Path $TestDrive "stdin.txt") -Raw -Encoding utf8) -split "\r?\n" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $rawLines[0] | Should -Be '{"type":"header","schema_version":1}'
        $rawLines[7] | Should -Be '{"type":"end"}'
        foreach ($index in 1..6) {
            $rawLines[$index] | Should -Match '^\{"type":"item","key":"[a-z_]+","item":\{'
            $rawLines[$index] | Should -Not -Match '(?:\{|,)\s+"|,\s*\}'
        }
    }

    It "returns a fixed producer failure when Docker cannot be started" {
        $missingDockerProcessParameters = @{
            DockerExecutable      = Join-Path $TestDrive "missing-docker"
            DockerPrefixArguments = @()
        }
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            [void]$Arguments
            throw "must not be called"
        }

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @missingDockerProcessParameters

        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        $result.Message | Should -Be "Hermes bootstrap secret retrieval failed."
        $global:LASTEXITCODE | Should -Be 1
    }

    It "restores a saturated 256-record error history after a secret-bearing producer failure" {
        $originalErrorHistory = @($global:Error)
        try {
            $global:Error.Clear()
            foreach ($index in 0..255) {
                [void]$global:Error.Insert(0, (New-HermesBootstrapTestErrorRecord -Message "saturated-baseline-$index"))
            }
            $baseline = @($global:Error)
            $baselineMessages = @($baseline | ForEach-Object { $_.Exception.Message })
            $secretMarker = "saturated-producer-secret-秘密"
            $env:HERMES_BOOTSTRAP_TEST_HANG = "1"
            $pidPath = Join-Path $TestDrive "pid"
            $invoker = {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
                [void]$Arguments
                if (-not $IsWindows) {
                    $deadline = [DateTime]::UtcNow.AddSeconds(1)
                    while (-not (Test-Path -LiteralPath $pidPath) -and [DateTime]::UtcNow -lt $deadline) {
                        Start-Sleep -Milliseconds 10
                    }
                }
                throw $secretMarker
            }.GetNewClosure()
            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters
            $watch.Stop()

            $result.Success | Should -BeFalse
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 1.8
            $actual = @($global:Error)
            $actual.Count | Should -Be 256
            @($actual | ForEach-Object { $_.Exception.Message }) | Should -Be $baselineMessages
            foreach ($index in 0..255) {
                [object]::ReferenceEquals($actual[$index], $baseline[$index]) | Should -BeTrue
            }
            Test-HermesBootstrapErrorGraphMarker -Roots $actual -Marker $secretMarker | Should -BeFalse
            if (-not $IsWindows) {
                $childProcessId = [int](Get-Content -LiteralPath $pidPath -Raw)
                { Get-Process -Id $childProcessId -ErrorAction Stop } | Should -Throw
            }
            else {
                @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$TestDrive*docker.cmd*" }).Count | Should -Be 0
            }
        }
        finally {
            Restore-HermesBootstrapTestErrorHistory -Snapshot $originalErrorHistory
        }
    }

    It "restores an empty error history after a secret-bearing producer failure" {
        $originalErrorHistory = @($global:Error)
        try {
            $global:Error.Clear()
            $secretMarker = "empty-baseline-secret-秘密"
            $invoker = {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
                [void]$Arguments
                throw $secretMarker
            }

            $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

            $result.Success | Should -BeFalse
            $global:Error.Count | Should -Be 0
            Test-HermesBootstrapErrorGraphMarker -Roots @($global:Error) -Marker $secretMarker | Should -BeFalse
        }
        finally {
            Restore-HermesBootstrapTestErrorHistory -Snapshot $originalErrorHistory
        }
    }

    It "restores an exact non-saturated error history after a secret-bearing producer failure" {
        $originalErrorHistory = @($global:Error)
        try {
            $global:Error.Clear()
            foreach ($marker in @("baseline-oldest", "baseline-middle", "baseline-newest")) {
                [void]$global:Error.Insert(0, (New-HermesBootstrapTestErrorRecord -Message $marker))
            }
            $baseline = @($global:Error)
            $secretMarker = "producer-secret-marker-秘密"
            $invoker = {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
                [void]$Arguments
                throw $secretMarker
            }

            $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

            $result.Success | Should -BeFalse
            $actual = @($global:Error)
            $actual.Count | Should -Be $baseline.Count
            foreach ($index in 0..($baseline.Count - 1)) {
                [object]::ReferenceEquals($actual[$index], $baseline[$index]) | Should -BeTrue
            }
            Test-HermesBootstrapErrorGraphMarker -Roots $actual -Marker $secretMarker | Should -BeFalse
        }
        finally {
            Restore-HermesBootstrapTestErrorHistory -Snapshot $originalErrorHistory
        }
    }

    It "removes nested item JSON parsing errors from global error history" {
        $originalErrorHistory = @($global:Error)
        try {
            $global:Error.Clear()
            $preExistingError = New-HermesBootstrapTestErrorRecord -Message "pre-existing-json-history"
            [void]$global:Error.Add($preExistingError)
            $secretMarker = "nested-json-secret-marker-秘密"
            $invoker = {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
                [void]$Arguments
                return "{`"value`":`"$secretMarker`""
            }

            $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

            $result.Success | Should -BeFalse
            $global:Error.Count | Should -Be 1
            [object]::ReferenceEquals($global:Error[0], $preExistingError) | Should -BeTrue
            Test-HermesBootstrapErrorGraphMarker -Roots @($global:Error) -Marker $secretMarker | Should -BeFalse
        }
        finally {
            Restore-HermesBootstrapTestErrorHistory -Snapshot $originalErrorHistory
        }
    }

    It "redacts all discovered field values from a failed bootstrap diagnostic and preserves its exit code" {
        $secret = "diagnostic-secret-value"
        $env:HERMES_BOOTSTRAP_TEST_EXIT = "23"
        $env:HERMES_BOOTSTRAP_TEST_STDERR = "bootstrap saw $secret"
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = $secret }) } | ConvertTo-Json -Compress
        }

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        $result.Message | Should -Match "exit code 23"
        $result.Message | Should -Match "\[REDACTED\]"
        $result.Message | Should -Not -Match ([regex]::Escape($secret))
        $result.Message | Should -Not -Match '"fields"|"id"'
        $global:LASTEXITCODE | Should -Be 23
    }

    It "decodes Docker output as UTF-8 before redacting a non-ASCII secret" {
        $secret = "認証情報-秘密値"
        $env:HERMES_BOOTSTRAP_TEST_EXIT = "24"
        $env:HERMES_BOOTSTRAP_TEST_STDERR = "Windows-style diagnostic: $secret"
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = $secret }) } | ConvertTo-Json -Compress
        }

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters

        $result.Message | Should -Match "\[REDACTED\]"
        $result.Message | Should -Not -Match ([regex]::Escape($secret))
        $global:LASTEXITCODE | Should -Be 24
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1") -Raw
        $source | Should -Match 'StandardOutputEncoding\s*=\s*\$utf8Encoding'
        $source | Should -Match 'StandardErrorEncoding\s*=\s*\$utf8Encoding'
    }

    It "closes stdin and reaps the Docker child when a later 1Password lookup fails" {
        $env:HERMES_BOOTSTRAP_TEST_HANG = "1"
        $script:producerCallCount = 0
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            $script:producerCallCount++
            if ($script:producerCallCount -eq 2) { throw "lookup failed with a secret that must not surface" }
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = "first-secret" }) } | ConvertTo-Json -Compress
        }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters
        $watch.Stop()

        $result.Success | Should -BeFalse
        $result.Message | Should -Be "Hermes bootstrap secret retrieval failed."
        $global:LASTEXITCODE | Should -Be 1
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 1.8
        if (-not $IsWindows) {
            $childProcessId = [int](Get-Content -LiteralPath (Join-Path $TestDrive "pid") -Raw)
            { Get-Process -Id $childProcessId -ErrorAction Stop } | Should -Throw
            $descendantPidPath = Join-Path $TestDrive "descendant-pid"
            if (Test-Path -LiteralPath $descendantPidPath) {
                $descendantProcessId = [int](Get-Content -LiteralPath $descendantPidPath -Raw)
                { Get-Process -Id $descendantProcessId -ErrorAction Stop } | Should -Throw
            }
        }
        else {
            @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$TestDrive*docker.cmd*" }).Count | Should -Be 0
        }
    }

    It "bounds normal bootstrap execution and reaps the process tree on timeout" {
        $env:HERMES_BOOTSTRAP_TEST_HANG = "1"
        $script:HermesBootstrapProcessTimeoutMilliseconds = 100
        $script:HermesBootstrapTerminationTimeoutMilliseconds = 1000
        $script:HermesBootstrapDrainTimeoutMilliseconds = 1000
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = "timeout-secret" }) } | ConvertTo-Json -Compress
        }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters
        $watch.Stop()

        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        $result.Message | Should -Be "Hermes bootstrap timed out."
        $global:LASTEXITCODE | Should -Be 124
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 1.8
        if (-not $IsWindows) {
            $childProcessId = [int](Get-Content -LiteralPath (Join-Path $TestDrive "pid") -Raw)
            { Get-Process -Id $childProcessId -ErrorAction Stop } | Should -Throw
            $descendantProcessId = [int](Get-Content -LiteralPath (Join-Path $TestDrive "descendant-pid") -Raw)
            { Get-Process -Id $descendantProcessId -ErrorAction Stop } | Should -Throw
        }
        else {
            @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$TestDrive*docker.cmd*" }).Count | Should -Be 0
        }
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1") -Raw
        $source | Should -Not -Match 'WaitForExit\(\)|GetAwaiter\(\)\.GetResult\(\)'
        $source | Should -Match '\.Kill\(\$true\)'
        $source | Should -Match 'WaitForExit\(\$TimeoutMilliseconds\)'
        $source | Should -Match '\.Wait\(\$TimeoutMilliseconds\)'
    }

    It "does not leak process or redirected-stream handles across repeated invocations" {
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = "repeat-secret" }) } | ConvertTo-Json -Compress
        }
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        $before = if ($IsWindows) {
            $currentProcess.HandleCount
        }
        else {
            [System.IO.Directory]::GetFiles("/dev/fd").Count
        }

        foreach ($iteration in 1..12) {
            $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters
            $result.Success | Should -BeTrue
        }
        $after = if ($IsWindows) {
            $currentProcess.Refresh()
            $currentProcess.HandleCount
        }
        else {
            [System.IO.Directory]::GetFiles("/dev/fd").Count
        }

        ($after - $before) | Should -BeLessOrEqual 4
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../lib/HermesBootstrap.ps1") -Raw
        foreach ($pattern in @(
                '\$process\.StandardInput\.Dispose\(\)',
                '\$process\.StandardOutput\.Dispose\(\)',
                '\$process\.StandardError\.Dispose\(\)',
                '\$stdoutDrain\.Dispose\(\)',
                '\$stderrDrain\.Dispose\(\)',
                '\$drainCancellation\.Dispose\(\)',
                '\$drain\.Dispose\(\)',
                '\$process\.Dispose\(\)'
            )) {
            $source | Should -Match $pattern
        }
    }

    It "drains large stdout and stderr without deadlocking" {
        $env:HERMES_BOOTSTRAP_TEST_LARGE_OUTPUT = "1"
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            return @{ id = "id-$($Arguments[2])"; fields = @(@{ label = "credential"; value = "safe-value" }) } | ConvertTo-Json -Compress
        }

        $result = Invoke-HermesBootstrap -ComposeFile "compose.yml" -DataDir "C:\Users\test\.hermes" -InvokeOnePasswordItem $invoker @script:dockerProcessParameters
        $watch.Stop()

        $result.Success | Should -BeTrue
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 10
    }
}
