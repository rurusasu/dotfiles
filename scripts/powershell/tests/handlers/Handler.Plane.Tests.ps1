#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Plane.ps1
}

Describe 'PlaneHandler' {
    BeforeEach {
        $script:handler = [PlaneHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:userProfile = Join-Path $TestDrive "user"
        $script:oldUserProfile = $env:USERPROFILE
        $script:bashCalls = @()
        $script:downloadedUrls = @()

        New-Item -ItemType Directory -Path $script:userProfile -Force | Out-Null
        $env:USERPROFILE = $script:userProfile

        Mock Write-Host { }
        Mock Get-Command {
            return [PSCustomObject]@{ Name = $Name; Source = "C:\tools\$Name.exe" }
        } -ParameterFilter { $Name -in @("docker", "bash") }
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }
        Mock Test-DockerDaemon { return $true }
        Mock Invoke-WebRequestSafe {
            param(
                [string]$Uri,
                [string]$OutFile
            )
            $script:downloadedUrls += $Uri
            Set-Content -LiteralPath $OutFile -Encoding UTF8 -Value "#!/bin/bash`necho plane"
        }
        Mock Invoke-PlaneBash {
            param(
                [string]$BashPath,
                [string]$WorkingDirectory,
                [string[]]$Arguments,
                [int]$TimeoutSeconds
            )
            $null = $BashPath
            $null = $TimeoutSeconds
            $script:bashCalls += [PSCustomObject]@{
                WorkingDirectory = $WorkingDirectory
                Arguments        = @($Arguments)
            }
            $global:LASTEXITCODE = 0
            return @("ok")
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:oldUserProfile
    }

    Context 'Constructor' {
        It 'should set installer metadata' {
            $handler.Name | Should -Be "Plane"
            $handler.Description | Should -Be "Plane Docker Compose セットアップ"
            $handler.Order | Should -Be 57
            $handler.RequiresAdmin | Should -Be $false
            $handler.Phase | Should -Be 2
            $handler.HttpPort | Should -Be 18080
            $handler.HttpsPort | Should -Be 18081
        }
    }

    Context 'Invoke-PlaneBash' {
        It 'should run setup scripts through a login shell so WSL profile paths are available' {
            $arguments = New-PlaneBashProcessArgument `
                -WorkingDirectory "C:\Users\KoheiMiki\plane-selfhost" `
                -Arguments @("./setup.sh", "install")

            $arguments | Should -BeOfType ([string])
            $arguments | Should -Match '^-lc\s+"'
            $arguments | Should -Not -Match "wslpath|cygpath"
            $arguments | Should -Match "/mnt/c/Users/KoheiMiki/plane-selfhost"
            $arguments | Should -Match ([regex]::Escape("./setup.sh"))
            $arguments | Should -Match "install"
        }

        It 'should patch setup.sh to prefer docker compose over the Windows docker-compose shim' {
            $setupPath = Join-Path $TestDrive "setup.sh"
            Set-Content -LiteralPath $setupPath -Encoding UTF8 -Value @'
#!/bin/bash
if command -v docker-compose &> /dev/null
then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi
'@

            Update-PlaneSetupScriptCompatibility -SetupPath $setupPath

            $content = Get-Content -LiteralPath $setupPath -Raw
            $content | Should -Match "docker compose version"
            $content.IndexOf('docker compose version') | Should -BeLessThan $content.IndexOf('command -v docker-compose')
            $content | Should -Match 'COMPOSE_CMD="docker compose"'
        }
    }

    Context 'CanApply' {
        It 'should return false when skipped by option' {
            $ctx.Options["SkipPlane"] = $true

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when disabled by option' {
            $ctx.Options["PlaneEnabled"] = $false

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when docker is unavailable' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "docker" }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when bash is unavailable' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "bash" }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when Docker daemon is not ready' {
            Mock Test-DockerDaemon { return $false }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return true when docker, bash, and daemon are available' {
            $handler.CanApply($ctx) | Should -Be $true

            Should -Invoke Test-DockerDaemon -Times 1 -ParameterFilter {
                $TimeoutSeconds -eq 15
            }
        }
    }

    Context 'Apply' {
        It 'should download official setup script, install Plane, update ports, and start services' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "http://127.0.0.1:18080"
            $script:downloadedUrls | Should -Contain "https://github.com/makeplane/plane/releases/latest/download/setup.sh"

            $selfhostDir = Join-Path $script:userProfile "plane-selfhost"
            $setupPath = Join-Path $selfhostDir "setup.sh"
            $setupPath | Should -Exist

            $script:bashCalls.Count | Should -Be 2
            $script:bashCalls[0].WorkingDirectory | Should -Be $selfhostDir
            $script:bashCalls[0].Arguments | Should -Be @("./setup.sh", "install")
            $script:bashCalls[1].Arguments | Should -Be @("./setup.sh", "start")

            $envPath = Join-Path $selfhostDir "plane-app\plane.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "(?m)^LISTEN_HTTP_PORT=18080\r?$"
            $envContent | Should -Match "(?m)^LISTEN_HTTPS_PORT=18081\r?$"
            $envContent | Should -Match "(?m)^WEB_URL=http://127.0.0.1:18080\r?$"
            $envContent | Should -Match "(?m)^CORS_ALLOWED_ORIGINS=http://127.0.0.1:18080\r?$"
            $envContent | Should -Not -Match "`r"
        }

        It 'should preserve unrelated plane.env values while updating the managed keys' {
            $selfhostDir = Join-Path $script:userProfile "plane-selfhost"
            $appDir = Join-Path $selfhostDir "plane-app"
            New-Item -ItemType Directory -Path $appDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $appDir "plane.env") -Encoding UTF8 -Value @(
                "LISTEN_HTTP_PORT=80",
                "WEB_URL=http://localhost",
                "CUSTOM=value"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath (Join-Path $appDir "plane.env") -Raw
            $envContent | Should -Match "(?m)^LISTEN_HTTP_PORT=18080\r?$"
            $envContent | Should -Match "(?m)^LISTEN_HTTPS_PORT=18081\r?$"
            $envContent | Should -Match "(?m)^WEB_URL=http://127.0.0.1:18080\r?$"
            $envContent | Should -Match "(?m)^CORS_ALLOWED_ORIGINS=http://127.0.0.1:18080\r?$"
            $envContent | Should -Match "(?m)^CUSTOM=value\r?$"
        }

        It 'should use port options when provided' {
            $ctx.Options["PlaneHttpPort"] = 19080
            $ctx.Options["PlaneHttpsPort"] = 19081

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile "plane-selfhost\plane-app\plane.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "(?m)^LISTEN_HTTP_PORT=19080\r?$"
            $envContent | Should -Match "(?m)^LISTEN_HTTPS_PORT=19081\r?$"
            $envContent | Should -Match "(?m)^WEB_URL=http://127.0.0.1:19080\r?$"
        }

        It 'should bootstrap the Plane admin, workspace, and API token when credentials are configured' {
            $ctx.Options["PlaneAdminEmail"] = "owner@example.com"
            $ctx.Options["PlaneAdminPassword"] = "login-password"
            $ctx.Options["PlaneApiToken"] = "plane_api_testtoken"
            $script:bootstrapScriptContent = ""
            Mock Invoke-PlaneBash {
                param(
                    [string]$BashPath,
                    [string]$WorkingDirectory,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $BashPath
                $null = $TimeoutSeconds
                if ($Arguments.Count -ge 3 -and $Arguments[0] -eq "docker" -and $Arguments[1] -eq "cp" -and $Arguments[2] -like "*/plane-bootstrap.py") {
                    $sourcePath = $Arguments[2] -replace '^/mnt/([a-z])/', '$1:/'
                    $sourcePath = $sourcePath.Replace("/", "\")
                    $script:bootstrapScriptContent = Get-Content -LiteralPath $sourcePath -Raw
                }
                $script:bashCalls += [PSCustomObject]@{
                    WorkingDirectory = $WorkingDirectory
                    Arguments        = @($Arguments)
                }
                $global:LASTEXITCODE = 0
                return @("ok")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true

            $selfhostDir = Join-Path $script:userProfile "plane-selfhost"
            $payloadPath = Join-Path $selfhostDir "plane-bootstrap-payload.json"
            $scriptPath = Join-Path $selfhostDir "plane-bootstrap.py"
            $script:bashCalls.Count | Should -Be 5
            $script:bashCalls[2].Arguments | Should -Be @("docker", "cp", (ConvertTo-PlaneBashPath -Path $payloadPath), "plane-app-api-1:/tmp/plane_bootstrap_payload.json")
            $script:bashCalls[3].Arguments | Should -Be @("docker", "cp", (ConvertTo-PlaneBashPath -Path $scriptPath), "plane-app-api-1:/tmp/plane_bootstrap.py")
            $script:bashCalls[4].Arguments | Should -Be @("docker", "exec", "plane-app-api-1", "sh", "-lc", "python3 manage.py shell < /tmp/plane_bootstrap.py && rm -f /tmp/plane_bootstrap.py /tmp/plane_bootstrap_payload.json")

            $payloadPath | Should -Not -Exist
            $scriptPath | Should -Not -Exist

            $script:bootstrapScriptContent | Should -Match '"dotfiles"'
            $script:bootstrapScriptContent | Should -Match '"article-collector"'
            $script:bootstrapScriptContent | Should -Match '"lifelog"'
            $script:bootstrapScriptContent | Should -Match 'ProjectIdentifier\.objects'
            $script:bootstrapScriptContent | Should -Match 'DEFAULT_STATES'
            $script:bootstrapScriptContent | Should -Match 'Issue\.issue_objects'
            $script:bootstrapScriptContent | Should -Not -Match 'workspace_seed'
        }

        It 'should return failure when setup install fails' {
            Mock Invoke-PlaneBash {
                param(
                    [string]$BashPath,
                    [string]$WorkingDirectory,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $BashPath
                $null = $WorkingDirectory
                $null = $TimeoutSeconds
                $script:bashCalls += [PSCustomObject]@{ Arguments = @($Arguments) }
                $global:LASTEXITCODE = 1
                return @("install failed")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "install"
            $script:bashCalls.Count | Should -Be 1
        }
    }
}
