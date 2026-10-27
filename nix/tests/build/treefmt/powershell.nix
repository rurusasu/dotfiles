# Exercise the configured formatter with no user modules and forbidden downloads.
{ pkgs, formatter }:
pkgs.runCommand "powershell-formatter-check" { } ''
  export HOME="$TMPDIR/empty-home"
  mkdir -p "$HOME"
  ${formatter.command} -NoProfile -NonInteractive -File ${pkgs.writeText "powershell-formatter-probe.ps1" ''
    $ErrorActionPreference = 'Stop'
    $env:PSModulePath = Join-Path $PSHOME 'Modules'
    $manifests = @(Get-ChildItem -LiteralPath $env:DOTFILES_PSSA_MODULE -Filter PSScriptAnalyzer.psd1 -Recurse -File)
    if ($manifests.Count -ne 1) { throw 'Expected exactly one PSScriptAnalyzer manifest in the nixpkgs PowerShell extension' }
    function global:Install-Module { throw 'Runtime module installation is forbidden' }
    function global:Save-Module { throw 'Runtime module downloads are forbidden' }
    function global:Invoke-WebRequest { throw 'Runtime network access is forbidden' }
    function global:Invoke-RestMethod { throw 'Runtime network access is forbidden' }
    $formatter = [scriptblock]::Create(${
      (value: "'" + builtins.replaceStrings [ "'" ] [ "''" ] value + "'") (
        builtins.elemAt formatter.options 2
      )
    } + ' @args')
    $directory = Join-Path $args[0] 'scripts/powershell'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $target = Join-Path $directory 'fixture.ps1'
    $label = -join @([char]0x672a, [char]0x8a2d, [char]0x5b9a)
    $source = "if(`$true){Write-Output '$label'}" + "`n"
    $expected = "if (`$true) { Write-Output '$label' }" + "`r`n"
    [IO.File]::WriteAllText($target, $source, [Text.UTF8Encoding]::new($false))
    $env:FILENAME = $null
    & $formatter $target
    if ([IO.File]::ReadAllText($target) -cne $expected) { throw 'Formatter did not produce the expected text and CRLF' }
    $bytes = [IO.File]::ReadAllBytes($target)
    if ([BitConverter]::ToString($bytes[0..2]) -ne 'EF-BB-BF') { throw 'Formatter did not add the required Unicode BOM' }
    $first = [Convert]::ToBase64String($bytes)
    [IO.File]::WriteAllText($target, $expected, [Text.UTF8Encoding]::new($false))
    $env:FILENAME = $target
    & $formatter
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne $first) { throw 'Formatter did not repair a missing BOM without changing formatted text' }
    $modified = [IO.File]::GetLastWriteTimeUtc($target)
    & $formatter
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne $first) { throw 'Formatter is not byte-idempotent' }
    if ([IO.File]::GetLastWriteTimeUtc($target) -ne $modified) { throw 'Formatter rewrote an unchanged file' }
    $env:FILENAME = $null
    foreach ($case in @(
      @{ Path = 'scripts/powershell/ascii.ps1'; Unicode = $false; Bom = $false; Expected = $false },
      @{ Path = 'scripts/powershell/data.psd1'; Unicode = $true; Bom = $false; Expected = $true },
      @{ Path = 'scripts/powershell/module.psm1'; Unicode = $true; Bom = $false; Expected = $true },
      @{ Path = 'chezmoi/unicode.ps1'; Unicode = $true; Bom = $false; Expected = $false },
      @{ Path = 'scripts/powershell/existing.ps1'; Unicode = $false; Bom = $true; Expected = $true }
    )) {
      $target = Join-Path (Join-Path $args[0] 'path with spaces') $case.Path
      New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
      $value = if ($case.Unicode) { $label } else { 'value' }
      $content = "@{ Name = '$value' }`r`n"
      [IO.File]::WriteAllText($target, $content, [Text.UTF8Encoding]::new($case.Bom))
      & $formatter $target
      $hasBom = [BitConverter]::ToString([IO.File]::ReadAllBytes($target)[0..2]) -eq 'EF-BB-BF'
      if ($hasBom -ne $case.Expected) { throw "Unexpected BOM for $($case.Path)" }
      if ([IO.File]::ReadAllText($target) -cne $content) { throw "Formatter changed formatted text in $($case.Path)" }
    }
    Write-Output 'Empty-HOME PowerShell formatting, encoding boundaries, BOM repair, CRLF, and idempotence passed without downloads'
  ''} "$TMPDIR/fixture"
  touch "$out"
''
