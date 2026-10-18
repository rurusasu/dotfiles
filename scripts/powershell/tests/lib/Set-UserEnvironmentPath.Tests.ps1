BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    $setterSource = (Get-Command Set-UserEnvironmentPath).ScriptBlock.ToString()
    $nativeWrite = '[System.Environment]::SetEnvironmentVariable("PATH", $Path, "User")'
    if (-not $setterSource.Contains($nativeWrite)) { throw 'Could not isolate the production User PATH write boundary' }
    # Run the shipped parameter checks and overflow guard with a fake final
    # write, so even an accidentally removed guard cannot change the registry.
    $isolatedSource = $setterSource.Replace($nativeWrite, '$script:fixtureUserPathWrites.Add($Path)')
    if ($isolatedSource.Contains('SetEnvironmentVariable')) { throw 'Native registry writer remains in the fixture' }
    $script:isolatedSetter = [scriptblock]::Create($isolatedSource)
}

Describe 'Set-UserEnvironmentPath Windows length boundary' {
    BeforeEach { $script:fixtureUserPathWrites = [Collections.Generic.List[string]]::new() }

    It 'should reject overflow before reaching the isolated registry write' {
        { & $script:isolatedSetter -Path ('X' * 32768) } | Should -Throw '*32767*32768*'
        $script:fixtureUserPathWrites.Count | Should -Be 0
    }

    It 'should allow the Windows boundary through the isolated registry write' {
        & $script:isolatedSetter -Path ('X' * 32767)
        $script:fixtureUserPathWrites.Count | Should -Be 1
        $script:fixtureUserPathWrites[0].Length | Should -Be 32767
    }
}
