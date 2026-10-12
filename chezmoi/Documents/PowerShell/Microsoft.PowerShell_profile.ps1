$weztermCommand = Get-Command wezterm -ErrorAction SilentlyContinue
if ($weztermCommand) {
    $weztermCompletion = & $weztermCommand.Source shell-completion --shell power-shell 2>$null | Out-String
    $completionMarker = '$completions = @(switch ($command) {'
    $domainCompletion = @'
if ($command -in @('wezterm;start', 'wezterm;cli;spawn') -and $commandElements.Count -gt 2) {
    $domainOptionIndex = $commandElements.Count - 1
    if ($commandElements[$domainOptionIndex].Value -eq $wordToComplete) {
        $domainOptionIndex--
    }
    $expectedDomainOption = if ($command -eq 'wezterm;start') { '--domain' } else { '--domain-name' }
    if ($domainOptionIndex -gt 1 -and $commandElements[$domainOptionIndex].Value -eq $expectedDomainOption) {
        [CompletionResult]::new('WSL:NixOS', 'WSL:NixOS', [CompletionResultType]::ParameterValue, 'NixOS WSL domain')
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
