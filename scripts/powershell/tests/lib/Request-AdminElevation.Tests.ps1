<#
.SYNOPSIS
    Request-AdminElevation.ps1 のテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/Request-AdminElevation.ps1
}

Describe 'Test-IsAdmin' {
    It 'should return boolean' {
        $result = Test-IsAdmin
        $result | Should -BeOfType [bool]
    }
}

Describe 'Exit-Script' {
    It 'should be a function' {
        Get-Command Exit-Script | Should -Not -BeNullOrEmpty
    }
}

Describe 'Request-AdminElevation' {
    BeforeEach {
        Mock Write-Host { }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    Context 'when running as administrator' {
        BeforeEach {
            Mock Test-IsAdmin { return $true }
        }

        It 'should not show UAC prompt' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Not -Invoke Start-Process
            Should -Not -Invoke Write-Host
        }

        It 'should return without action' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            { Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params } | Should -Not -Throw
        }
    }

    Context 'when not running as administrator' {
        BeforeEach {
            Mock Test-IsAdmin { return $false }
            Mock Exit-Script { }
        }

        It 'should show UAC message' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "Administrator privileges are required"
            }
        }

        It 'should start elevated process' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Start-Process -ParameterFilter {
                $FilePath -eq "pwsh" -and
                $Verb -eq "RunAs"
            }
        }

        It 'should pass script path in arguments' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            Request-AdminElevation -ScriptPath "C:\my scripts\test.ps1" -BoundParameters $params

            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match "C:\\my scripts\\test.ps1"
            }
        }

        It 'should call Exit-Script with exit code 0' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Exit-Script -ParameterFilter {
                $ExitCode -eq 0
            }
        }
    }

    Context 'parameter passing' {
        BeforeEach {
            Mock Test-IsAdmin { return $false }
            Mock Exit-Script { }
        }

        It 'should pass string parameters' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()
            $params["DistroName"] = "MyNixOS"

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match "-DistroName" -and
                $ArgumentList -match "MyNixOS"
            }
        }

        It 'should pass switch parameters' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()
            $params["Verbose"] = [switch]$true

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match "-Verbose"
            }
        }

        It 'should pass hashtable parameters' {
            $params = [System.Collections.Generic.Dictionary[string, object]]::new()
            $params["Options"] = @{ SkipVhdExpand = $true; Retries = 5 }

            Request-AdminElevation -ScriptPath "C:\test.ps1" -BoundParameters $params

            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match "-Options" -and
                $ArgumentList -match "@\{"
            }
        }
    }
}
