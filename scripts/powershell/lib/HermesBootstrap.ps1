<#!
.SYNOPSIS
    Streams the Hermes bootstrap 1Password payload to the container.
#>

if (-not ("HermesBootstrapBoundedDrain" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class HermesBootstrapBoundedDrain : IDisposable
{
    private readonly object syncRoot = new object();
    private readonly StringBuilder buffer = new StringBuilder();
    private readonly int maximum;

    public HermesBootstrapBoundedDrain(int maximum) { this.maximum = maximum; }

    public async Task DrainAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        var chars = new char[4096];
        try
        {
            int count;
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                count = await reader.ReadAsync(chars, 0, chars.Length).ConfigureAwait(false);
                if (count <= 0) { break; }
                lock (syncRoot)
                {
                    var remaining = maximum - buffer.Length;
                    if (remaining > 0) { buffer.Append(chars, 0, Math.Min(remaining, count)); }
                }
            }
        }
        catch (OperationCanceledException)
        {
            if (!cancellationToken.IsCancellationRequested) { throw; }
        }
        catch (ObjectDisposedException)
        {
            if (!cancellationToken.IsCancellationRequested) { throw; }
        }
    }

    public string Text { get { lock (syncRoot) { return buffer.ToString(); } } }

    public void Dispose()
    {
        lock (syncRoot) { buffer.Clear(); }
    }
}
'@
}

if (-not ("HermesBootstrapProcessArgument" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;

public static class HermesBootstrapProcessArgument
{
    public static string Quote(string argument)
    {
        if (argument == null) { throw new ArgumentNullException("argument"); }
        if (argument.Length > 0 && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return argument;
        }

        var quoted = new StringBuilder(argument.Length + 2);
        quoted.Append('"');
        var backslashes = 0;
        foreach (var character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }
            quoted.Append('\\', backslashes);
            backslashes = 0;
            quoted.Append(character);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
'@
}

if (-not ("HermesBootstrapErrorHistory" -as [type])) {
    Add-Type -TypeDefinition @'
using System.Collections;

public static class HermesBootstrapErrorHistory
{
    public static void Restore(ArrayList errors, object[] snapshot)
    {
        try
        {
            errors.Clear();
            if (snapshot == null) { return; }
            foreach (var errorRecord in snapshot) { errors.Add(errorRecord); }
        }
        catch { }
    }
}
'@
}

$script:HermesBootstrapProcessTimeoutMilliseconds = 30 * 60 * 1000
$script:HermesBootstrapTerminationTimeoutMilliseconds = 5000
$script:HermesBootstrapDrainTimeoutMilliseconds = 5000
$script:HermesBootstrapAllowedOnePasswordItems = @(
    [PSCustomObject]@{ key = "dashboard"; account = "my.1password.com"; vault = "openclaw"; item = "Hermes Agent Dashboard" },
    [PSCustomObject]@{ key = "github"; account = "my.1password.com"; vault = "openclaw"; item = "GitHubUsedOpenClawPAT" },
    [PSCustomObject]@{ key = "slack_default"; account = "my.1password.com"; vault = "openclaw"; item = "SlackBot-OpenClaw" },
    [PSCustomObject]@{ key = "slack_rick"; account = "my.1password.com"; vault = "openclaw"; item = "SlackBot-Rick" },
    [PSCustomObject]@{ key = "slack_hoffman"; account = "my.1password.com"; vault = "openclaw"; item = "SlackBot-Hoffman" },
    [PSCustomObject]@{ key = "slack_risarisa"; account = "my.1password.com"; vault = "openclaw"; item = "SlackBot-Risarisa" },
    [PSCustomObject]@{ key = "slack_nancy"; account = "my.1password.com"; vault = "openclaw"; item = "SlackBot-Nancy" }
)

function ConvertFrom-HermesBootstrapJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Json,
        [Parameter(Mandatory)]
        [int]$Depth
    )

    $command = Get-Command -Name ConvertFrom-Json -CommandType Cmdlet -ErrorAction Stop
    if ($command.Parameters.ContainsKey("Depth")) {
        return ($Json | ConvertFrom-Json -Depth $Depth -ErrorAction Stop)
    }
    return ($Json | ConvertFrom-Json -ErrorAction Stop)
}

function New-HermesBootstrapProcessStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$DataDir
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($property in @("StandardInputEncoding", "StandardOutputEncoding", "StandardErrorEncoding")) {
        if ($null -ne $startInfo.PSObject.Properties[$property]) {
            $startInfo.$property = $utf8Encoding
        }
    }
    $startInfo.EnvironmentVariables["HERMES_DATA_DIR"] = $DataDir
    if ($null -ne $startInfo.PSObject.Properties["ArgumentList"]) {
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
    }
    else {
        $startInfo.Arguments = @(
            $Arguments | ForEach-Object { [HermesBootstrapProcessArgument]::Quote($_) }
        ) -join " "
    }
    return $startInfo
}

function Get-HermesBootstrapSecretPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile
    )

    $arguments = @(
        "compose", "-f", $ComposeFile,
        "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "secret-plan"
    )
    $output = @(Invoke-Docker -Arguments $arguments)
    if ($LASTEXITCODE -ne 0) {
        throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan retrieval failed.")
    }

    try {
        $plan = ConvertFrom-HermesBootstrapJson -Json ($output -join "`n") -Depth 32
        if (-not (Test-HermesBootstrapSecretPlan -Plan $plan)) {
            throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan is invalid.")
        }
        return $plan
    }
    catch {
        throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan is invalid.")
    }
}

function Test-HermesBootstrapSecretPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    if (-not (Test-HermesBootstrapPropertySet -Value $Plan -Names @("schema_version", "items"))) { return $false }
    if ($Plan.schema_version -isnot [long] -and $Plan.schema_version -isnot [int]) { return $false }
    if ($Plan.schema_version -ne 1) { return $false }

    $items = @($Plan.items)
    if ($items.Count -ne 7) { return $false }

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    for ($itemIndex = 0; $itemIndex -lt $items.Count; $itemIndex++) {
        $item = $items[$itemIndex]
        if (-not (Test-HermesBootstrapPropertySet -Value $item -Names @("key", "account", "vault", "item", "fields"))) {
            return $false
        }
        foreach ($name in @("key", "account", "vault", "item")) {
            if ($item.$name -isnot [string] -or
                [string]::IsNullOrWhiteSpace($item.$name) -or
                $item.$name.Trim() -cne $item.$name) { return $false }
        }
        $allowedItem = $script:HermesBootstrapAllowedOnePasswordItems[$itemIndex]
        foreach ($name in @("key", "account", "vault", "item")) {
            if ($item.$name -cne $allowedItem.$name) { return $false }
        }
        if (-not $keys.Add($item.key)) { return $false }

        if ($item.fields -is [string] -or $item.fields -isnot [System.Collections.IEnumerable]) { return $false }
        $fields = @($item.fields)
        if ($fields.Count -eq 0) { return $false }
        $fieldNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($field in $fields) {
            if (-not (Test-HermesBootstrapPropertySet -Value $field -Names @("canonical_name", "labels"))) { return $false }
            if ($field.canonical_name -isnot [string] -or
                [string]::IsNullOrWhiteSpace($field.canonical_name) -or
                $field.canonical_name.Trim() -cne $field.canonical_name) { return $false }
            if (-not $fieldNames.Add($field.canonical_name)) { return $false }
            if ($field.labels -is [string] -or $field.labels -isnot [System.Collections.IEnumerable]) { return $false }
            $labels = @($field.labels)
            if ($labels.Count -eq 0) { return $false }
            foreach ($label in $labels) {
                if ($label -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($label) -or
                    $label.Trim() -cne $label) { return $false }
            }
        }
    }

    return $true
}

function Test-HermesBootstrapPropertySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    if ($null -eq $Value) { return $false }
    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $expected = @($Names | Sort-Object)
    return $actual.Count -eq $expected.Count -and $null -eq (Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
}

$script:DefaultOnePasswordInvoker = {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    $output = @(& op @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw [System.InvalidOperationException]::new("Hermes bootstrap 1Password retrieval failed.")
    }
    return $output
}

function Invoke-HermesBootstrapCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    try {
        [void](& $Action)
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-HermesBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,
        [Parameter(Mandatory)]
        [string]$DataDir,
        [scriptblock]$InvokeOnePasswordItem = $script:DefaultOnePasswordInvoker,
        [ValidateNotNullOrEmpty()]
        [string]$DockerExecutable = "docker",
        [AllowEmptyCollection()]
        [string[]]$DockerPrefixArguments = @()
    )

    $plan = Get-HermesBootstrapSecretPlan -ComposeFile $ComposeFile
    [System.Management.Automation.ErrorRecord[]]$errorHistoryBeforeProducer = @($global:Error)
    $process = $null
    $processStarted = $false
    $producerFailed = $false
    $payloadWriteFailed = $false
    $secretValues = [System.Collections.Generic.List[string]]::new()
    $drain = [HermesBootstrapBoundedDrain]::new(65536)
    $drainCancellation = [System.Threading.CancellationTokenSource]::new()
    $stdoutDrain = $null
    $stderrDrain = $null
    $invokerOutput = $null
    $item = $null
    $record = $null
    $processInput = $null

    try {
        try {
            $processArguments = @($DockerPrefixArguments) + @(
                "compose", "-f", $ComposeFile,
                "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "apply"
            )
            $startInfo = New-HermesBootstrapProcessStartInfo `
                -Executable $DockerExecutable `
                -Arguments $processArguments `
                -DataDir $DataDir

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            if (-not $process.Start()) {
                throw [System.InvalidOperationException]::new("Hermes bootstrap process could not be started.")
            }
            $processStarted = $true
            $processInput = if ($null -ne $startInfo.PSObject.Properties["StandardInputEncoding"]) {
                $process.StandardInput
            }
            else {
                $writer = [System.IO.StreamWriter]::new(
                    $process.StandardInput.BaseStream,
                    [System.Text.UTF8Encoding]::new($false),
                    4096,
                    $false
                )
                $writer.AutoFlush = $true
                $writer
            }
            $stdoutDrain = $drain.DrainAsync($process.StandardOutput, $drainCancellation.Token)
            $stderrDrain = $drain.DrainAsync($process.StandardError, $drainCancellation.Token)
            $processInput.NewLine = "`n"
            try {
                $processInput.WriteLine('{"type":"header","schema_version":1}')
            }
            catch {
                $payloadWriteFailed = $true
                throw
            }

            foreach ($planItem in @($plan.items)) {
                try {
                    $onePasswordArguments = @(
                        "item", "get", $planItem.item,
                        "--account", $planItem.account,
                        "--vault", $planItem.vault,
                        "--format", "json"
                    )
                    $invokerOutput = @(& $InvokeOnePasswordItem @onePasswordArguments)
                    $item = ConvertTo-HermesBootstrapItemObject -Output $invokerOutput
                    foreach ($value in Get-HermesBootstrapItemFieldValue -Item $item) {
                        $secretValues.Add($value)
                    }

                    $record = [ordered]@{ type = "item"; key = $planItem.key; item = $item }
                    try {
                        $processInput.WriteLine(($record | ConvertTo-Json -Compress -Depth 64))
                    }
                    catch {
                        $payloadWriteFailed = $true
                        throw
                    }
                }
                finally {
                    if ($item -is [System.IDisposable]) {
                        [void](Invoke-HermesBootstrapCleanup -Action { $item.Dispose() })
                    }
                    $record = $null
                    $item = $null
                    $invokerOutput = $null
                }
            }
            try {
                $processInput.WriteLine('{"type":"end"}')
            }
            catch {
                $payloadWriteFailed = $true
                throw
            }
        }
        catch {
            $producerFailed = $true
            Set-Variable -Name PSItem -Value $null -Scope Local
        }
        finally {
            if ($processStarted) {
                [void](Invoke-HermesBootstrapCleanup -Action { $processInput.Close() })
            }
        }

        if ($producerFailed) {
            $consumerCompleted = $payloadWriteFailed -and $processStarted -and (
                Wait-HermesBootstrapProcess -Process $process -TimeoutMilliseconds 1000
            )
            if ($consumerCompleted -and $process.ExitCode -ne 0) {
                $exitCode = $process.ExitCode
                $global:LASTEXITCODE = $exitCode
                $drainsCompleted = Complete-HermesBootstrapProcessDrain `
                    -Process $process `
                    -StdoutDrain $stdoutDrain `
                    -StderrDrain $stderrDrain `
                    -Cancellation $drainCancellation `
                    -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds
                if (-not $drainsCompleted) {
                    return [PSCustomObject]@{
                        Success = $false
                        Changed = $false
                        Message = "Hermes bootstrap output drain timed out."
                    }
                }

                $diagnostics = ConvertTo-HermesBootstrapRedactedText -Text $drain.Text -Values $secretValues
                $message = "Hermes bootstrap failed (exit code $exitCode)."
                if (-not [string]::IsNullOrWhiteSpace($diagnostics)) {
                    $message = "$message $diagnostics"
                }
                return [PSCustomObject]@{ Success = $false; Changed = $false; Message = $message }
            }

            $terminated = Stop-HermesBootstrapProcess `
                -Process $process `
                -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds
            [void](Complete-HermesBootstrapProcessDrain `
                    -Process $process `
                    -StdoutDrain $stdoutDrain `
                    -StderrDrain $stderrDrain `
                    -Cancellation $drainCancellation `
                    -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds)
            $global:LASTEXITCODE = 1
            $message = if ($terminated) {
                "Hermes bootstrap secret retrieval failed."
            }
            else {
                "Hermes bootstrap process termination failed."
            }
            return [PSCustomObject]@{ Success = $false; Changed = $false; Message = $message }
        }

        $completed = Wait-HermesBootstrapProcess `
            -Process $process `
            -TimeoutMilliseconds $script:HermesBootstrapProcessTimeoutMilliseconds
        if (-not $completed) {
            [void](Stop-HermesBootstrapProcess `
                    -Process $process `
                    -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds)
            [void](Complete-HermesBootstrapProcessDrain `
                    -Process $process `
                    -StdoutDrain $stdoutDrain `
                    -StderrDrain $stderrDrain `
                    -Cancellation $drainCancellation `
                    -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds)
            $global:LASTEXITCODE = 124
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Message = "Hermes bootstrap timed out."
            }
        }

        $exitCode = $process.ExitCode
        $global:LASTEXITCODE = $exitCode
        $drainsCompleted = Complete-HermesBootstrapProcessDrain `
            -Process $process `
            -StdoutDrain $stdoutDrain `
            -StderrDrain $stderrDrain `
            -Cancellation $drainCancellation `
            -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds
        if (-not $drainsCompleted) {
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Message = "Hermes bootstrap output drain timed out."
            }
        }
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                Changed = $true
                Message = "Hermes bootstrap completed."
            }
        }

        $diagnostics = ConvertTo-HermesBootstrapRedactedText -Text $drain.Text -Values $secretValues
        $message = "Hermes bootstrap failed (exit code $exitCode)."
        if (-not [string]::IsNullOrWhiteSpace($diagnostics)) {
            $message = "$message $diagnostics"
        }
        return [PSCustomObject]@{ Success = $false; Changed = $false; Message = $message }
    }
    finally {
        if ($item -is [System.IDisposable]) {
            [void](Invoke-HermesBootstrapCleanup -Action { $item.Dispose() })
        }
        if ($processStarted -and -not (Wait-HermesBootstrapProcess -Process $process -TimeoutMilliseconds 0)) {
            [void](Stop-HermesBootstrapProcess `
                    -Process $process `
                    -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds)
        }
        if (($stdoutDrain -and -not $stdoutDrain.IsCompleted) -or
            ($stderrDrain -and -not $stderrDrain.IsCompleted)) {
            [void](Invoke-HermesBootstrapCleanup -Action { $drainCancellation.Cancel() })
        }
        if ($processInput) {
            [void](Invoke-HermesBootstrapCleanup -Action { $processInput.Dispose() })
        }
        if ($process) {
            [void](Invoke-HermesBootstrapCleanup -Action { $process.StandardInput.Dispose() })
            [void](Invoke-HermesBootstrapCleanup -Action { $process.StandardOutput.Dispose() })
            [void](Invoke-HermesBootstrapCleanup -Action { $process.StandardError.Dispose() })
        }
        if ($stdoutDrain -and $stdoutDrain.IsCompleted) {
            [void](Invoke-HermesBootstrapCleanup -Action { $stdoutDrain.Dispose() })
        }
        if ($stderrDrain -and $stderrDrain.IsCompleted) {
            [void](Invoke-HermesBootstrapCleanup -Action { $stderrDrain.Dispose() })
        }
        [void](Invoke-HermesBootstrapCleanup -Action { $drainCancellation.Dispose() })
        [void](Invoke-HermesBootstrapCleanup -Action { $drain.Dispose() })
        if ($process) {
            [void](Invoke-HermesBootstrapCleanup -Action { $process.Dispose() })
        }
        $record = $null
        $item = $null
        $invokerOutput = $null
        $value = $null
        $secretValues = $null
        Set-Variable -Name PSItem -Value $null -Scope Local
        [HermesBootstrapErrorHistory]::Restore($global:Error, $errorHistoryBeforeProducer)
        $errorHistoryBeforeProducer = $null
    }
}

function ConvertTo-HermesBootstrapItemObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Output
    )

    if ($Output.Count -eq 1 -and $Output[0] -isnot [string]) {
        return $Output[0]
    }
    $json = @($Output | ForEach-Object { [string]$_ }) -join "`n"
    try {
        return (ConvertFrom-HermesBootstrapJson -Json $json -Depth 64)
    }
    catch {
        throw [System.InvalidOperationException]::new("Hermes bootstrap 1Password retrieval failed.")
    }
}

function Get-HermesBootstrapItemFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    if ($null -eq $Item -or $null -eq $Item.fields) { return @() }
    return @($Item.fields |
            ForEach-Object {
                if ($null -ne $_ -and $_.value -is [string] -and $_.value.Length -gt 0) {
                    $_.value
                }
            })
}

function ConvertTo-HermesBootstrapRedactedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Values
    )

    $redacted = $Text
    foreach ($value in @($Values | Sort-Object Length -Descending -Unique)) {
        $redacted = $redacted.Replace($value, "[REDACTED]")
    }
    return $redacted.Trim()
}

function Stop-HermesBootstrapProcess {
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    if ($null -eq $Process) { return $true }
    if (Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds 0) { return $true }
    if (-not (Invoke-HermesBootstrapCleanup -Action { $Process.Kill($true) })) {
        [void](Invoke-HermesBootstrapCleanup -Action { $Process.Kill() })
    }
    if (Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds $TimeoutMilliseconds) { return $true }

    [void](Invoke-HermesBootstrapCleanup -Action { $Process.Kill() })
    return Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds $TimeoutMilliseconds
}

function Wait-HermesBootstrapProcess {
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    if ($null -eq $Process) { return $true }
    try {
        if ($Process.HasExited) { return $true }
        return $Process.WaitForExit($TimeoutMilliseconds)
    }
    catch {
        return $true
    }
}

function Complete-HermesBootstrapProcessDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process,
        [System.Threading.Tasks.Task]$StdoutDrain,
        [System.Threading.Tasks.Task]$StderrDrain,
        [Parameter(Mandatory)]
        [System.Threading.CancellationTokenSource]$Cancellation,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    $cancellationSource = $Cancellation
    $completed = $true
    foreach ($task in @($StdoutDrain, $StderrDrain)) {
        if ($null -eq $task) { continue }
        try {
            if (-not $task.Wait($TimeoutMilliseconds)) { $completed = $false }
        }
        catch {
            $completed = $false
        }
    }
    if ($completed) { return $true }

    [void](Invoke-HermesBootstrapCleanup -Action { $cancellationSource.Cancel() })
    if ($Process) {
        [void](Invoke-HermesBootstrapCleanup -Action { $Process.StandardOutput.Dispose() })
        [void](Invoke-HermesBootstrapCleanup -Action { $Process.StandardError.Dispose() })
    }
    foreach ($task in @($StdoutDrain, $StderrDrain)) {
        if ($null -eq $task -or $task.IsCompleted) { continue }
        [void](Invoke-HermesBootstrapCleanup -Action { [void]$task.Wait($TimeoutMilliseconds) })
    }
    return $false
}
