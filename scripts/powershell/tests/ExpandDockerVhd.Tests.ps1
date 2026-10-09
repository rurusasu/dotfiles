BeforeAll {
    $script:target = Join-Path $PSScriptRoot '../../../windows/expand-docker-vhd.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:target, [ref]$null, [ref]$null)
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DiskpartVhdxVirtualSizeGB' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    function diskpart { param($Option, $ScriptPath) throw 'Use the DiskPart mock' }
}

Describe 'Docker VHD virtual capacity detection' {
    It 'should parse the optional Windows script with ANSI codepage <codepage>' -ForEach @(
        @{ codepage = 1252 }
        @{ codepage = 932 }
    ) {
        $reader = [IO.StreamReader]::new($script:target, [Text.Encoding]::GetEncoding($codepage), $true)
        try { $source = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
    }

    It 'should read virtual capacity from DiskPart in <unit>' -ForEach @(
        @{ text = 'Virtual size: 64 GB'; expected = 64; unit = 'GB' }
        @{ text = 'Virtual size: 1 TB'; expected = 1024; unit = 'TB' }
        @{ text = 'Virtual size: 65536 MB'; expected = 64; unit = 'MB' }
        @{ text = '仮想サイズ: 64 GB'; expected = 64; unit = 'Japanese GB' }
    ) {
        $script:diskpartText = $text
        Mock diskpart {
            param($Option, $ScriptPath)
            (Get-Content -LiteralPath $ScriptPath -Raw) | Should -Match 'detail vdisk'
            $global:LASTEXITCODE = 0
            return @($script:diskpartText, 'Physical size: 3 GB')
        }

        Get-DiskpartVhdxVirtualSizeGB -Path 'D:\Docker\disk.vhdx' | Should -Be $expected
    }

    It 'should reject output from a failed DiskPart process' {
        Mock diskpart { $global:LASTEXITCODE = 1; return 'Virtual size: 64 GB' }
        Get-DiskpartVhdxVirtualSizeGB -Path 'D:\Docker\disk.vhdx' | Should -Be 0
    }

    It 'should not mistake physical allocation for virtual capacity' {
        Mock diskpart { $global:LASTEXITCODE = 0; return 'Physical size: 3 GB' }
        Get-DiskpartVhdxVirtualSizeGB -Path 'D:\Docker\disk.vhdx' | Should -Be 0
    }
}
