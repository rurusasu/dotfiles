function codex {
    $codexBin = if ($env:LOCALAPPDATA) {
        [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin'))
    }
    else { $null }
    $codexBinPrefix = if ($codexBin) { $codexBin + [IO.Path]::DirectorySeparatorChar } else { $null }
    $codexApplication = Get-Command codex -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object {
            -not $codexBinPrefix -or
            -not [IO.Path]::GetFullPath($_.Source).StartsWith($codexBinPrefix, [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
    if ($codexApplication) {
        & $codexApplication.Source @args
        return
    }

    $codexRuntime = $null
    if ($codexBin) {
        $runtimeFiles = @(
            'codex.exe'
            'codex-code-mode-host.exe'
            'codex-command-runner.exe'
            'codex-windows-sandbox-setup.exe'
        )
        $codexRuntime = Get-ChildItem -LiteralPath $codexBin -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $runtimeDirectory = $_.FullName
                @($runtimeFiles | Where-Object {
                        -not (Test-Path -LiteralPath (Join-Path $runtimeDirectory $_) -PathType Leaf)
                    }).Count -eq 0
            } |
            ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'codex.exe') } |
            Sort-Object -Property @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, FullName |
            Select-Object -First 1
    }

    if (-not $codexRuntime) {
        $global:LASTEXITCODE = 127
        Write-Error 'Codex CLI was not found on PATH or in a complete installed Codex app runtime.' -Category ObjectNotFound -ErrorId CodexCliNotFound -ErrorAction Stop
    }

    # The desktop app runtime lacks the standalone CLI package needed by the daemon.
    if ($args -contains '--no-daemon') {
        & $codexRuntime.FullName @args
    }
    else {
        & $codexRuntime.FullName --no-daemon @args
    }
}

$weztermCommand = Get-Command wezterm -ErrorAction SilentlyContinue
if ($weztermCommand) {
    $weztermCompletion = & $weztermCommand.Source shell-completion --shell power-shell 2>$null | Out-String
    $completionMarker = '$completions = @(switch ($command) {'
    $domainCompletion = @'
if ($command -in @('wezterm;start', 'wezterm;cli;spawn') -and $commandElements.Count -gt 2) {
    $previousElement = $commandElements |
        Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
        Select-Object -Last 1
    $expectedDomainOption = if ($command -eq 'wezterm;start') { '--domain' } else { '--domain-name' }
    if ($previousElement -is [StringConstantExpressionAst] -and $previousElement.Value -eq $expectedDomainOption) {
        if ('WSL:NixOS' -like "$wordToComplete*") {
            [CompletionResult]::new('WSL:NixOS', 'WSL:NixOS', [CompletionResultType]::ParameterValue, 'NixOS WSL domain')
        }
        return
    }
}
'@

    if ($weztermCompletion.Contains($completionMarker)) {
        $weztermCompletion = $weztermCompletion.Replace($completionMarker, "$domainCompletion`n$completionMarker")
        Invoke-Expression $weztermCompletion
    }
}

if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected) {
    $psReadLineOptions = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
    if ($psReadLineOptions -and $psReadLineOptions.Parameters.ContainsKey('PredictionViewStyle')) {
        # Show matching history while typing; ordinary command completion stays on Tab.
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView
        Set-PSReadLineKeyHandler -Chord Tab -Function TabCompleteNext
    }
}
