# Exercise the configured formatter with no user modules and forbidden downloads.
{ pkgs, formatter }:
let
  quotePowerShell = value: "'" + builtins.replaceStrings [ "'" ] [ "''" ] value + "'";
  probe = pkgs.writeText "powershell-formatter-probe.ps1" ''
    $ErrorActionPreference = 'Stop'
    $env:PSModulePath = Join-Path $PSHOME 'Modules'
    function global:Install-Module { throw 'Runtime module installation is forbidden' }
    function global:Save-Module { throw 'Runtime module downloads are forbidden' }
    function global:Invoke-WebRequest { throw 'Runtime network access is forbidden' }
    function global:Invoke-RestMethod { throw 'Runtime network access is forbidden' }
    $formatter = [scriptblock]::Create(${quotePowerShell (builtins.elemAt formatter.options 2)} + ' @args')
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
    $modified = [IO.File]::GetLastWriteTimeUtc($target)
    $env:FILENAME = $target
    & $formatter
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne $first) { throw 'Formatter is not byte-idempotent' }
    if ([IO.File]::GetLastWriteTimeUtc($target) -ne $modified) { throw 'Formatter rewrote an unchanged file' }
    Write-Output 'Empty-HOME PowerShell formatting, BOM, CRLF, and idempotence passed without downloads'
  '';
in
pkgs.runCommand "powershell-formatter-check" { } ''
  export HOME="$TMPDIR/empty-home"
  mkdir -p "$HOME"
  ${formatter.command} -NoProfile -NonInteractive -File ${probe} "$TMPDIR/fixture"
  touch "$out"
''
