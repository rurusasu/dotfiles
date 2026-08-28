#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.MLflow.ps1
}

Describe 'MLflowHandler' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'dotfiles'
        $script:composeDir = Join-Path $script:root 'docker/mlflow'
        $script:composeFile = Join-Path $script:composeDir 'compose.yml'
        New-Item -ItemType Directory -Path $script:composeDir -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}'
        $script:ctx = [SetupContext]::new($script:root)
        $script:handler = [MLflowHandler]::new()
        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()
        Mock Get-Command { [PSCustomObject]@{ Name = $Name } }
        Mock Test-DockerDaemon { $true }
        Mock Invoke-Docker {
            param([string[]]$Arguments)
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments -contains 'inspect') {
                $global:LASTEXITCODE = 1
                return
            }
            $global:LASTEXITCODE = 0
        }
    }

    It 'sets Phase 2 metadata after Docker and before Hindsight' {
        $handler.Name | Should -Be 'MLflow'
        $handler.Description | Should -Be 'Shared MLflow Gateway Docker service'
        $handler.Order | Should -Be 54
        $handler.RequiresAdmin | Should -BeFalse
        $handler.Phase | Should -Be 2
    }

    It 'is disabled unless WithMLflow is enabled' {
        $handler.CanApply($ctx) | Should -BeFalse

        $ctx.Options['WithMLflow'] = $true
        $handler.CanApply($ctx) | Should -BeTrue
    }

    It 'skips when Docker is unavailable or not ready' {
        $ctx.Options['WithMLflow'] = $true
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'docker' }
        $handler.CanApply($ctx) | Should -BeFalse

        Mock Get-Command { [PSCustomObject]@{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
        Mock Test-DockerDaemon { $false }
        $handler.CanApply($ctx) | Should -BeFalse
    }

    It 'skips when the MLflow compose file is missing' {
        $ctx.Options['WithMLflow'] = $true
        Remove-Item -LiteralPath $composeFile -Force

        $handler.CanApply($ctx) | Should -BeFalse
    }

    It 'uses the shared network and reconciles the pinned MLflow container' {
        $ctx.Options['WithMLflow'] = $true

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeTrue
        $dockerCalls | Should -Be @(
            'network inspect local-ai-services',
            'network create local-ai-services',
            "compose -f $composeFile config --quiet",
            "compose -f $composeFile pull mlflow",
            "compose -f $composeFile up -d --force-recreate --remove-orphans --wait mlflow",
            "compose -f $composeFile exec -T mlflow python /opt/mlflow/configure.py --base-url http://127.0.0.1:5000 --manifest /opt/mlflow/endpoints.yml"
        )
    }

    It 'does not recreate the shared network when it already exists' {
        $ctx.Options['WithMLflow'] = $true
        Mock Invoke-Docker {
            param([string[]]$Arguments)
            $script:dockerCalls.Add(($Arguments -join ' '))
            $global:LASTEXITCODE = 0
        }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeTrue
        $dockerCalls | Should -Not -Contain 'network create local-ai-services'
    }

    It 'reports a network creation failure' {
        $ctx.Options['WithMLflow'] = $true
        Mock Invoke-Docker {
            param([string[]]$Arguments)
            $script:dockerCalls.Add(($Arguments -join ' '))
            $global:LASTEXITCODE = if ($Arguments -contains 'create') { 17 } else { 1 }
        }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'network setup failed'
    }
}
