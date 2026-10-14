#Requires -Version 5.1
<#
.SYNOPSIS
    Merge the exported desktop bindings into the active PowerToys profile.
.DESCRIPTION
    Runtime changes are opt-in. All existing JSON is validated before writes.
    The ownership file records the exact previous mapping, so user edits to it
    are preserved when the shared chord changes.
#>
[CmdletBinding()]
param(
    [string]$BindingJson,
    [string]$ContractJson,
    [string]$ActionScriptPath = (Join-Path $env:LOCALAPPDATA 'dotfiles/keybindings/Invoke-DesktopAction.ps1'),
    [string]$PowerToysDirectory = (Join-Path $env:LOCALAPPDATA 'Microsoft/PowerToys'),
    [switch]$RestartPowerToys
)

$ErrorActionPreference = 'Stop'

function Get-JsonDocument {
    param([string]$Path, [object]$Default)
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    if ($exists) {
        $json = [IO.File]::ReadAllText($Path)
        if (-not $json.TrimStart().StartsWith('{')) { throw "Expected a JSON object: $Path" }
        $value = $json | ConvertFrom-Json
    }
    else { $value = $Default }
    if ($value -isnot [pscustomobject]) { throw "Expected a JSON object: $Path" }
    [pscustomobject]@{ Path = $Path; Value = $value; Before = if ($exists) { $value | ConvertTo-Json -Depth 100 -Compress } else { $null } }
}

function Set-JsonProperty {
    param([object]$Object, [string]$Name, [AllowNull()][object]$Value)
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-JsonObjectProperty {
    param([object]$Object, [string]$Name)
    if (-not $Object.PSObject.Properties[$Name]) { Set-JsonProperty $Object $Name ([pscustomobject]@{}) }
    if ($Object.$Name -isnot [pscustomobject]) { throw "Expected a JSON object for $Name" }
    $Object.$Name
}

function Initialize-JsonArrayProperty {
    param([object]$Object, [string]$Name)
    if (-not $Object.PSObject.Properties[$Name]) { Set-JsonProperty $Object $Name @() }
    if ($Object.$Name -isnot [array]) { throw "Expected a JSON array for $Name" }
    foreach ($item in $Object.$Name) {
        if ($item -isnot [pscustomobject]) { throw "Expected JSON objects in $Name" }
    }
}

function Get-KeyboardProfilePath {
    param([string]$Directory, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ne $Name.Trim() -or
        $Name -match '[\\/:*?"<>|\x00-\x1f]' -or $Name.EndsWith('.') -or
        $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
        throw 'Invalid PowerToys active profile name'
    }
    Join-Path $Directory ($Name + '.json')
}

function Get-EmptyKeyboardProfile {
    [pscustomobject]@{
        remapKeys            = [pscustomobject]@{ inProcess = @() }
        remapKeysToText      = [pscustomobject]@{ inProcess = @() }
        remapShortcuts       = [pscustomobject]@{ global = @(); appSpecific = @() }
        remapShortcutsToText = [pscustomobject]@{ global = @(); appSpecific = @() }
    }
}

function Initialize-KeyboardProfile {
    param([object]$Profile)
    foreach ($name in @('remapKeys', 'remapKeysToText')) {
        $section = Get-JsonObjectProperty $Profile $name
        Initialize-JsonArrayProperty $section 'inProcess'
    }
    foreach ($name in @('remapShortcuts', 'remapShortcutsToText')) {
        $section = Get-JsonObjectProperty $Profile $name
        Initialize-JsonArrayProperty $section 'global'
        Initialize-JsonArrayProperty $section 'appSpecific'
    }
}

function Get-CanonicalShortcut {
    param([string]$Keys)
    # PowerToys serializes modifiers in Win, Ctrl, Alt, Shift order.
    $aliases = @{ '91' = '260'; '92' = '260'; '162' = '17'; '163' = '17'; '164' = '18'; '165' = '18'; '160' = '16'; '161' = '16' }
    $codes = @($Keys -split ';' | ForEach-Object { if ($aliases.ContainsKey($_)) { $aliases[$_] } else { $_ } })
    if ($codes.Count -eq 1) { return $Keys }
    $modifiers = @($codes[0..($codes.Count - 2)])
    foreach ($code in $modifiers) {
        if ($code -notin @('260', '17', '18', '16') -or @($modifiers | Where-Object { $_ -eq $code }).Count -ne 1) { return $Keys }
    }
    ((@('260', '17', '18', '16') | Where-Object { $modifiers -contains $_ }) -join ';') + ';' + $codes[-1]
}

function Test-JsonEqual {
    param([object]$First, [object]$Second)
    if ($null -eq $First -or $null -eq $Second) { return $null -eq $First -and $null -eq $Second }
    if ($First -is [pscustomobject] -or $Second -is [pscustomobject]) {
        if ($First -isnot [pscustomobject] -or $Second -isnot [pscustomobject]) { return $false }
        $firstProperties = @($First.PSObject.Properties)
        $secondProperties = @($Second.PSObject.Properties)
        if ($firstProperties.Count -ne $secondProperties.Count) { return $false }
        foreach ($property in $firstProperties) {
            $matching = @($secondProperties | Where-Object { $_.Name -ceq $property.Name })
            if ($matching.Count -ne 1 -or -not (Test-JsonEqual $property.Value $matching[0].Value)) { return $false }
        }
        return $true
    }
    if ($First -is [array] -or $Second -is [array]) {
        if ($First -isnot [array] -or $Second -isnot [array] -or $First.Count -ne $Second.Count) { return $false }
        for ($index = 0; $index -lt $First.Count; $index++) {
            if (-not (Test-JsonEqual $First[$index] $Second[$index])) { return $false }
        }
        return $true
    }
    $First.GetType() -eq $Second.GetType() -and $First -ceq $Second
}

function Write-JsonDocument {
    param([object]$Document)
    $serialized = $Document.Value | ConvertTo-Json -Depth 100 -Compress
    if ($Document.Before -ceq $serialized) { return }
    $directory = Split-Path -Parent $Document.Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ([guid]::NewGuid().ToString() + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($Document.Value | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Document.Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Send-KeyboardSettingsEvent {
    try { $settingsEvent = [Threading.EventWaitHandle]::OpenExisting('PowerToys_KeyboardManager_Event_Settings') }
    catch [Threading.WaitHandleCannotBeOpenedException] { return }
    try { [void]$settingsEvent.Set() }
    finally { $settingsEvent.Dispose() }
}

function Get-BindingShortcut {
    param([object]$Binding)
    $modifierCodes = @{ super = '260'; ctrl = '17'; alt = '18'; shift = '16' }
    $keyCodes = @{ enter = 13; space = 32; slash = 191; comma = 188; print = 44; mute = 173; backspace = 8; tab = 9; escape = 27; backtick = 192; minus = 189; equal = 187; left = 37; up = 38; right = 39; down = 40; home = 36; end = 35; pageup = 33; pagedown = 34; page_up = 33; page_down = 34; period = 190; semicolon = 186 }
    if ($Binding -isnot [pscustomobject] -or $Binding.key -isnot [string] -or $Binding.modifiers -isnot [array]) {
        throw 'Expected a binding with a key and modifiers array'
    }
    $keyCode = if ($Binding.key -cmatch '^[a-z]$') { [int][char]$Binding.key.ToUpperInvariant() }
    elseif ($Binding.key -cmatch '^[0-9]$') { [int][char]$Binding.key }
    elseif ($keyCodes.ContainsKey($Binding.key)) { $keyCodes[$Binding.key] }
    else { throw "Unsupported desktop key: $($Binding.key)" }
    $seenModifiers = @{}
    foreach ($modifier in $Binding.modifiers) {
        if ($modifier -isnot [string] -or $modifier -cnotin @('super', 'ctrl', 'alt', 'shift') -or $seenModifiers.ContainsKey($modifier)) {
            throw 'Unsupported or duplicate desktop modifier'
        }
        $seenModifiers[$modifier] = $true
    }
    $codes = @(@('super', 'ctrl', 'alt', 'shift') | Where-Object { $seenModifiers.ContainsKey($_) } | ForEach-Object { $modifierCodes[$_] }) + @([string]$keyCode)
    $codes -join ';'
}

function Get-DesiredKeyboardMapping {
    param([object]$Binding, [string]$ActionScriptPath, [switch]$LegacyTerminal, [switch]$Disabled)
    $keys = Get-BindingShortcut $Binding
    $action = if ($Disabled) { 'disabled' } else { $Binding.action }
    if (-not $Disabled -and ($action -isnot [string] -or $action -cnotmatch '^[a-z][a-z0-9-]*$')) { throw 'Invalid desktop action name' }
    # Clipboard editing goes through the runtime so WSLg Ghostty receives
    # Ctrl+Shift+C/V instead of terminal control characters such as Ctrl+C.
    $targets = @{ clipboard = '260;86'; 'screenshot-clipboard' = '260;16;83' }
    $target = if ($Disabled) { '256' } elseif ($targets.ContainsKey($action)) { $targets[$action] } else { $null }
    $mapping = [pscustomobject][ordered]@{ originalKeys = $keys; exactMatch = $true; operationType = 0 }
    $editorMapping = [pscustomobject][ordered]@{
        OriginalKeys = $keys; TargetKeys = ''; TargetApp = ''; OperationType = 0; TargetText = ''
        ProgramPath = ''; ProgramArgs = ''; StartInDirectory = ''; Elevation = 0; IfRunningAction = 1; Visibility = 1; UriToOpen = ''
    }
    if ($target) {
        Set-JsonProperty $mapping 'newRemapKeys' $target
        $editorMapping.TargetKeys = $target
        $operation = 'RemapShortcut'
    }
    else {
        $programPath = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
        $programArgs = '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ActionScriptPath + '" -Action "' + $action + '"'
        if ($LegacyTerminal) {
            $programPath = '%SystemRoot%\System32\wsl.exe'
            $programArgs = '--distribution NixOS --cd ~ --exec bash -lc ghostty'
        }
        # Windows PowerShell's C# compiler resolves relative framework
        # references against the launch directory. PowerToys ships .NET
        # assemblies there, so launch the desktop runtime from its own folder.
        $startInDirectory = if ($LegacyTerminal) { '' } else { Split-Path -Parent $ActionScriptPath }
        $mapping.operationType = 1
        Set-JsonProperty $mapping 'runProgramFilePath' $programPath
        Set-JsonProperty $mapping 'runProgramArgs' $programArgs
        Set-JsonProperty $mapping 'runProgramStartInDir' $startInDirectory
        Set-JsonProperty $mapping 'runProgramElevationLevel' 0
        Set-JsonProperty $mapping 'runProgramAlreadyRunningAction' 1
        Set-JsonProperty $mapping 'runProgramStartWindowType' 1
        Set-JsonProperty $mapping 'unicodeText' '*Unsupported*'
        $editorMapping.TargetKeys = $keys
        $editorMapping.OperationType = 1
        $editorMapping.ProgramPath = $programPath
        $editorMapping.ProgramArgs = $programArgs
        $editorMapping.StartInDirectory = $startInDirectory
        $operation = 'RunProgram'
    }
    [pscustomobject]@{ action = $action; scope = 'global'; mapping = $mapping; editorMapping = $editorMapping; operation = $operation; editorId = $null }
}

function Get-DesiredGhosttyTransport {
    param([object]$Transport)
    if ($Transport -isnot [pscustomobject] -or $Transport.action -isnot [string] -or
        $Transport.action -cnotmatch '^[a-z][a-z0-9-]*$' -or $Transport.targetApp -isnot [string] -or
        $Transport.targetApp -notmatch '^[a-zA-Z0-9._-]+\.exe$') { throw 'Invalid Ghostty transport mapping' }
    $sourceKeys = Get-BindingShortcut $Transport.source
    $targetKeys = Get-BindingShortcut $Transport.target
    $targetApp = $Transport.targetApp.ToLowerInvariant()
    $mapping = [pscustomobject][ordered]@{
        originalKeys = $sourceKeys; exactMatch = $true; operationType = 0
        newRemapKeys = $targetKeys; targetApp = $targetApp
    }
    $editorMapping = [pscustomobject][ordered]@{
        OriginalKeys = $sourceKeys; TargetKeys = $targetKeys; TargetApp = $targetApp; OperationType = 0; TargetText = ''
        ProgramPath = ''; ProgramArgs = ''; StartInDirectory = ''; Elevation = 0; IfRunningAction = 1; Visibility = 1; UriToOpen = ''
    }
    [pscustomobject]@{ action = $Transport.action; scope = 'appSpecific'; mapping = $mapping; editorMapping = $editorMapping; operation = 'RemapShortcut'; editorId = $null }
}

function Get-KeyboardMappingIdentity {
    param([object]$Mapping, [string]$Scope)
    $application = if ($Scope -eq 'appSpecific') { ([string]$Mapping.targetApp).ToLowerInvariant() } else { '' }
    $Scope + '|' + $application + '|' + (Get-CanonicalShortcut $Mapping.originalKeys)
}

function Get-OwnedKeyboardMappings {
    param([object]$Document)
    if (-not $Document.Before) { return }
    if ($Document.Value.profile -isnot [string]) { throw 'Invalid dotfiles keyboard ownership profile' }
    if ($Document.Value.PSObject.Properties['mappings']) {
        if ($Document.Value.mappings -isnot [array]) { throw 'Invalid dotfiles keyboard ownership mappings' }
        $entries = @($Document.Value.mappings)
    }
    else { $entries = @([pscustomobject]@{ mapping = $Document.Value.mapping; editorId = $Document.Value.editorId; editorMapping = $Document.Value.editorMapping }) }
    foreach ($entry in $entries) {
        if ($entry -isnot [pscustomobject] -or $entry.mapping -isnot [pscustomobject] -or $entry.mapping.originalKeys -isnot [string]) {
            throw 'Invalid dotfiles keyboard ownership mapping'
        }
        if (-not $entry.PSObject.Properties['scope']) {
            Set-JsonProperty $entry 'scope' $(if ([string]::IsNullOrEmpty($entry.mapping.targetApp)) { 'global' } else { 'appSpecific' })
        }
        if ($entry.scope -cnotin @('global', 'appSpecific')) { throw 'Invalid dotfiles keyboard ownership scope' }
        $entry
    }
}

function Merge-KeyboardProfile {
    param([object]$Document, [array]$Desired, [array]$Owned)
    foreach ($scope in @('global', 'appSpecific')) {
        $desiredScope = @($Desired | Where-Object { $_.scope -eq $scope })
        $ownedScope = @($Owned | Where-Object { $_.scope -eq $scope })
        $inserted = @{}
        $entries = @()
        foreach ($entry in $Document.Value.remapShortcuts.$scope) {
            $identity = Get-KeyboardMappingIdentity $entry $scope
            $wanted = @($desiredScope | Where-Object { (Get-KeyboardMappingIdentity $_.mapping $scope) -eq $identity })
            if ($wanted.Count -gt 0) {
                if (-not $inserted.ContainsKey($identity)) { $entries += $wanted[0].mapping; $inserted[$identity] = $true }
            }
            else {
                $previouslyOwned = @($ownedScope | Where-Object { Test-JsonEqual $_.mapping $entry })
                if ($previouslyOwned.Count -eq 0) { $entries += $entry }
            }
        }
        foreach ($wanted in $desiredScope) {
            if (-not $inserted.ContainsKey((Get-KeyboardMappingIdentity $wanted.mapping $scope))) { $entries += $wanted.mapping }
        }
        Set-JsonProperty $Document.Value.remapShortcuts $scope $entries
        # A desired shortcut must not also exist in the same scoped text table.
        $desiredIdentities = @($desiredScope | ForEach-Object { Get-KeyboardMappingIdentity $_.mapping $scope })
        Set-JsonProperty $Document.Value.remapShortcutsToText $scope @($Document.Value.remapShortcutsToText.$scope | Where-Object { (Get-KeyboardMappingIdentity $_ $scope) -notin $desiredIdentities })
    }
}

function Merge-KeyboardEditor {
    param([object]$Editor, [array]$Desired, [array]$Owned)
    $dictionary = Get-JsonObjectProperty $Editor.Value 'ShortcutSettingsDictionary'
    $operationIndex = Get-JsonObjectProperty $Editor.Value 'ShortcutsByOperationType'
    $profileIndex = Get-JsonObjectProperty $Editor.Value 'ProfileDictionary'
    $removedIds = @()
    foreach ($entry in @($dictionary.PSObject.Properties)) {
        $shortcut = $entry.Value.Shortcut
        $wanted = @($Desired | Where-Object { ([string]$shortcut.TargetApp) -eq ([string]$_.editorMapping.TargetApp) -and (Get-CanonicalShortcut $shortcut.OriginalKeys) -eq $_.mapping.originalKeys })
        $previouslyOwned = @($Owned | Where-Object { $entry.Name -eq $_.editorId -and $_.editorMapping -is [pscustomobject] -and (Test-JsonEqual $shortcut $_.editorMapping) })
        if ($wanted.Count -gt 0 -and -not $wanted[0].editorId) {
            $wanted[0].editorId = $entry.Name
            foreach ($field in $wanted[0].editorMapping.PSObject.Properties) { Set-JsonProperty $shortcut $field.Name $field.Value }
            Set-JsonProperty $entry.Value 'IsActive' $true
        }
        elseif ($wanted.Count -gt 0 -or $previouslyOwned.Count -gt 0) {
            $removedIds += $entry.Name
            $dictionary.PSObject.Properties.Remove($entry.Name)
        }
    }
    foreach ($wanted in $Desired) {
        if (-not $wanted.editorId) {
            $wanted.editorId = [guid]::NewGuid().ToString()
            Set-JsonProperty $dictionary $wanted.editorId ([pscustomobject]@{ Id = $wanted.editorId; Shortcut = $wanted.editorMapping; Profiles = @(); IsActive = $true })
        }
    }
    $desiredIds = @($Desired | ForEach-Object { $_.editorId })
    foreach ($entry in @($operationIndex.PSObject.Properties)) {
        $ids = @($entry.Value | Where-Object { $_ -notin $removedIds -and $_ -notin $desiredIds })
        Set-JsonProperty $operationIndex $entry.Name $ids
    }
    foreach ($operation in @('RunProgram', 'RemapShortcut')) {
        $ids = @($operationIndex.$operation | Where-Object { $null -ne $_ }) + @($Desired | Where-Object { $_.operation -eq $operation } | ForEach-Object { $_.editorId })
        if ($ids.Count -gt 0 -or $operationIndex.PSObject.Properties[$operation]) { Set-JsonProperty $operationIndex $operation $ids }
    }
    foreach ($entry in @($profileIndex.PSObject.Properties)) {
        Set-JsonProperty $profileIndex $entry.Name @($entry.Value | Where-Object { $_ -notin $removedIds })
    }
    # Record the actual merged shortcut, including any fields preserved from the editor.
    foreach ($wanted in $Desired) { $wanted.editorMapping = $dictionary.($wanted.editorId).Shortcut }
}

function Invoke-PowerToysKeyboardSync {
    [CmdletBinding()]
    param(
        [string]$BindingJson,
        [string]$ContractJson,
        [string]$ActionScriptPath = (Join-Path $env:LOCALAPPDATA 'dotfiles/keybindings/Invoke-DesktopAction.ps1'),
        [string]$PowerToysDirectory = (Join-Path $env:LOCALAPPDATA 'Microsoft/PowerToys'),
        [switch]$RestartPowerToys
    )

    if ([string]::IsNullOrWhiteSpace($BindingJson) -eq [string]::IsNullOrWhiteSpace($ContractJson)) { throw 'Specify exactly one of ContractJson or BindingJson' }
    $legacyTerminal = -not [string]::IsNullOrWhiteSpace($BindingJson)
    $colorBinding = $null
    $disabledBindings = @()
    $ghosttyTransport = @()
    if ($legacyTerminal) {
        if (-not $BindingJson.TrimStart().StartsWith('{')) { throw 'Expected a terminal binding JSON object' }
        $binding = $BindingJson | ConvertFrom-Json
        if ($binding.action -cne 'terminal' -or $binding.key -cne 'enter' -or $binding.modifiers -isnot [array] -or $binding.modifiers.Count -eq 0) {
            throw 'Expected terminal/enter with a nonempty modifiers array'
        }
        $bindings = @($binding)
    }
    else {
        if (-not $ContractJson.TrimStart().StartsWith('{')) { throw 'Expected a desktop contract JSON object' }
        $contract = $ContractJson | ConvertFrom-Json
        if ($contract -isnot [pscustomobject] -or $contract.windows -isnot [pscustomobject] -or $contract.windows.bindings -isnot [array]) { throw 'Expected windows.bindings in the desktop contract' }
        $bindings = $contract.windows.bindings
        if ($contract.windows.PSObject.Properties['disabledShortcuts']) {
            if ($contract.windows.disabledShortcuts -isnot [array]) { throw 'Expected windows.disabledShortcuts array' }
            $disabledBindings = $contract.windows.disabledShortcuts
        }
        if ($contract.windows.PSObject.Properties['ghosttyTransport']) {
            if ($contract.windows.ghosttyTransport -isnot [array]) { throw 'Expected windows.ghosttyTransport array' }
            $ghosttyTransport = $contract.windows.ghosttyTransport
        }
        $ActionScriptPath = [IO.Path]::GetFullPath($ActionScriptPath)
        if ($ActionScriptPath.Contains('"') -or $ActionScriptPath -match '[\r\n]') { throw 'Invalid desktop action script path' }
    }
    $desired = @()
    $desiredKeys = @{}
    foreach ($binding in $bindings) {
        $mapping = Get-DesiredKeyboardMapping $binding $ActionScriptPath -LegacyTerminal:$legacyTerminal
        if ($desiredKeys.ContainsKey($mapping.mapping.originalKeys)) { throw 'Duplicate desktop shortcut in the exported contract' }
        $desiredKeys[$mapping.mapping.originalKeys] = $true
        if ($binding.action -ceq 'color-picker') {
            if ($colorBinding) { throw 'ColorPicker supports one activation shortcut' }
            $colorBinding = $binding
        }
        else { $desired += $mapping }
    }
    foreach ($binding in $disabledBindings) {
        $mapping = Get-DesiredKeyboardMapping $binding $ActionScriptPath -Disabled
        if ($desiredKeys.ContainsKey($mapping.mapping.originalKeys)) { throw 'A disabled desktop shortcut conflicts with an action' }
        $desiredKeys[$mapping.mapping.originalKeys] = $true
        $desired += $mapping
    }
    $transportIdentities = @{}
    foreach ($transport in $ghosttyTransport) {
        $mapping = Get-DesiredGhosttyTransport $transport
        $identity = Get-KeyboardMappingIdentity $mapping.mapping $mapping.scope
        if ($transportIdentities.ContainsKey($identity)) { throw 'Duplicate Ghostty transport shortcut in the exported contract' }
        $transportIdentities[$identity] = $true
        $desired += $mapping
    }

    # Read and validate every PowerToys input before changing any document.
    $PowerToysDirectory = [IO.Path]::GetFullPath($PowerToysDirectory)
    $keyboardDirectory = Join-Path $PowerToysDirectory 'Keyboard Manager'
    $root = Get-JsonDocument (Join-Path $PowerToysDirectory 'settings.json') ([pscustomobject]@{})
    $module = Get-JsonDocument (Join-Path $keyboardDirectory 'settings.json') ([pscustomobject]@{ name = 'Keyboard Manager'; version = '1'; properties = [pscustomobject]@{} })
    $properties = Get-JsonObjectProperty $module.Value 'properties'
    $activeConfiguration = Get-JsonObjectProperty $properties 'activeConfiguration'
    if (-not $activeConfiguration.PSObject.Properties['value']) { Set-JsonProperty $activeConfiguration 'value' 'default' }
    if ($activeConfiguration.value -isnot [string]) { throw 'Invalid PowerToys active profile name' }
    $profileName = $activeConfiguration.value
    $profile = Get-JsonDocument (Get-KeyboardProfilePath $keyboardDirectory $profileName) (Get-EmptyKeyboardProfile)
    Initialize-KeyboardProfile $profile.Value
    # Retain the existing filename so installations from the terminal-only version migrate.
    $owner = Get-JsonDocument (Join-Path $PowerToysDirectory 'dotfiles-terminal-binding.json') ([pscustomobject]@{})
    $owned = @(Get-OwnedKeyboardMappings $owner)
    $previousProfile = $null
    if ($owner.Before) {
        $previousPath = Get-KeyboardProfilePath $keyboardDirectory $owner.Value.profile
        if ($previousPath -ne $profile.Path -and (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
            $previousProfile = Get-JsonDocument $previousPath (Get-EmptyKeyboardProfile)
            Initialize-KeyboardProfile $previousProfile.Value
        }
    }
    $editorPath = Join-Path $keyboardDirectory 'editorSettings.json'
    $editor = if (Test-Path -LiteralPath $editorPath -PathType Leaf) { Get-JsonDocument $editorPath ([pscustomobject]@{}) } else { $null }
    if ($editor) {
        $dictionary = Get-JsonObjectProperty $editor.Value 'ShortcutSettingsDictionary'
        $operationIndex = Get-JsonObjectProperty $editor.Value 'ShortcutsByOperationType'
        $profileIndex = Get-JsonObjectProperty $editor.Value 'ProfileDictionary'
        foreach ($entry in $dictionary.PSObject.Properties) {
            if ($entry.Value -isnot [pscustomobject] -or $entry.Value.Shortcut -isnot [pscustomobject]) { throw 'Invalid Keyboard Manager editor mapping' }
        }
        foreach ($index in @($operationIndex, $profileIndex)) {
            foreach ($entry in $index.PSObject.Properties) {
                if ($entry.Value -isnot [array]) { throw 'Invalid Keyboard Manager editor index' }
            }
        }
    }
    $enabled = Get-JsonObjectProperty $root.Value 'enabled'
    if ($enabled.PSObject.Properties['Keyboard Manager'] -and $enabled.'Keyboard Manager' -isnot [bool]) { throw 'Invalid Keyboard Manager enabled flag' }
    $wasEnabled = $enabled.'Keyboard Manager' -eq $true
    Set-JsonProperty $enabled 'Keyboard Manager' $true
    $color = $null
    $colorOwner = $null
    $previousColor = $owner.Value.colorPicker
    if ($previousColor -and ($previousColor -isnot [pscustomobject] -or $previousColor.activation -isnot [pscustomobject])) { throw 'Invalid dotfiles ColorPicker ownership' }
    $wasColorEnabled = $enabled.ColorPicker -eq $true
    if ($colorBinding -or $previousColor) {
        if ($enabled.PSObject.Properties['ColorPicker'] -and $enabled.ColorPicker -isnot [bool]) { throw 'Invalid ColorPicker enabled flag' }
        $color = Get-JsonDocument (Join-Path $PowerToysDirectory 'ColorPicker/settings.json') ([pscustomobject]@{ name = 'ColorPicker'; version = '2.1'; properties = [pscustomobject]@{} })
        $colorProperties = Get-JsonObjectProperty $color.Value 'properties'
        if ($colorBinding) {
            $previousActivation = $colorProperties.ActivationShortcut
            $previousActivationPresent = $null -ne $colorProperties.PSObject.Properties['ActivationShortcut']
            $previousEnabled = $enabled.ColorPicker
            $previousEnabledPresent = $null -ne $enabled.PSObject.Properties['ColorPicker']
            if ($previousColor -and (Test-JsonEqual $previousColor.activation $previousActivation)) {
                $previousActivation = $previousColor.previousActivation
                $previousActivationPresent = $previousColor.previousActivationPresent -eq $true
                if ($previousColor.PSObject.Properties['previousEnabledPresent']) {
                    $previousEnabled = $previousColor.previousEnabled
                    $previousEnabledPresent = $previousColor.previousEnabledPresent -eq $true
                }
            }
            $colorKeys = (Get-BindingShortcut $colorBinding) -split ';'
            $activation = [pscustomobject]@{
                win = $colorBinding.modifiers -contains 'super'; ctrl = $colorBinding.modifiers -contains 'ctrl'
                alt = $colorBinding.modifiers -contains 'alt'; shift = $colorBinding.modifiers -contains 'shift'
                code = [int]$colorKeys[-1]; key = ''
            }
            Set-JsonProperty $colorProperties 'ActivationShortcut' $activation
            Set-JsonProperty $enabled 'ColorPicker' $true
            $colorOwner = [pscustomobject]@{
                activation = $activation; previousActivation = $previousActivation; previousActivationPresent = $previousActivationPresent
                previousEnabled = $previousEnabled; previousEnabledPresent = $previousEnabledPresent
            }
        }
        elseif (Test-JsonEqual $colorProperties.ActivationShortcut $previousColor.activation) {
            if ($previousColor.previousActivationPresent -eq $true) { Set-JsonProperty $colorProperties 'ActivationShortcut' $previousColor.previousActivation }
            else { $colorProperties.PSObject.Properties.Remove('ActivationShortcut') }
            if ($enabled.ColorPicker -eq $true -and $previousColor.PSObject.Properties['previousEnabledPresent']) {
                if ($previousColor.previousEnabledPresent -eq $true) { Set-JsonProperty $enabled 'ColorPicker' $previousColor.previousEnabled }
                else { $enabled.PSObject.Properties.Remove('ColorPicker') }
            }
        }
    }

    if ($previousProfile) { Merge-KeyboardProfile $previousProfile @() $owned }
    $profileOwned = if ($owner.Before -and $owner.Value.profile -eq $profileName) { $owned } else { @() }
    Merge-KeyboardProfile $profile $desired $profileOwned
    if ($editor) { Merge-KeyboardEditor $editor $desired $owned }
    $owner.Value = [pscustomobject][ordered]@{
        version = 2; profile = $profileName
        mappings    = @($desired | ForEach-Object { [pscustomobject]@{ action = $_.action; scope = $_.scope; mapping = $_.mapping; editorId = $_.editorId; editorMapping = if ($editor) { $_.editorMapping } else { $null } } })
        colorPicker = $colorOwner
    }
    $profileChanged = $profile.Before -cne ($profile.Value | ConvertTo-Json -Depth 100 -Compress)
    $colorChanged = $color -and $color.Before -cne ($color.Value | ConvertTo-Json -Depth 100 -Compress)
    $colorEnableChanged = $color -and ($wasColorEnabled -ne ($enabled.ColorPicker -eq $true))
    $documents = @($profile, $module, $editor, $previousProfile, $owner, $color, $root) | Where-Object { $null -ne $_ }
    $stoppedRunners = @()
    try {
        if ($RestartPowerToys -and (-not $wasEnabled -or $colorChanged -or $colorEnableChanged)) {
            $installPaths = @((Join-Path $env:LOCALAPPDATA 'PowerToys/PowerToys.exe'), (Join-Path $env:ProgramFiles 'PowerToys/PowerToys.exe'))
            foreach ($runner in @(Get-Process -Name PowerToys -ErrorAction SilentlyContinue)) {
                $runnerPath = $runner.Path
                if ($runnerPath -notin $installPaths) { continue }
                Stop-Process -Id $runner.Id -Force -ErrorAction Stop
                $stoppedRunners += $runnerPath
                if (-not $runner.WaitForExit(5000)) { throw 'PowerToys runner did not exit before settings update' }
            }
        }
        foreach ($document in $documents) { Write-JsonDocument $document }
        if ($RestartPowerToys -and $wasEnabled -and $profileChanged -and $stoppedRunners.Count -eq 0) { Send-KeyboardSettingsEvent }
    }
    finally {
        foreach ($runnerPath in $stoppedRunners) { Start-Process -FilePath $runnerPath -WindowStyle Hidden | Out-Null }
    }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-PowerToysKeyboardSync @PSBoundParameters }
