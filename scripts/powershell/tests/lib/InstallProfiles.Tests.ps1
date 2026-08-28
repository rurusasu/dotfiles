#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/InstallProfiles.ps1
}

Describe 'Resolve-DotfilesInstallOption' {
    It 'keeps the default install core-only' {
        $result = Resolve-DotfilesInstallOption -Options @{}

        $result.WithOllama | Should -BeFalse
        $result.WithDocker | Should -BeFalse
        $result.WithMLflow | Should -BeFalse
        $result.WithHindsight | Should -BeFalse
        $result.WithHermes | Should -BeFalse
        $result.WithChrome | Should -BeFalse
        $result.WithDiscord | Should -BeFalse
        $result.WithChromium | Should -BeFalse
    }

    It 'enables only Ollama for WithOllama' {
        $result = Resolve-DotfilesInstallOption -Options @{} -WithOllama

        $result.WithOllama | Should -BeTrue
        $result.WithDocker | Should -BeFalse
        $result.WithMLflow | Should -BeFalse
        $result.WithHindsight | Should -BeFalse
        $result.WithHermes | Should -BeFalse
    }

    It 'enables only Docker for WithDocker' {
        $result = Resolve-DotfilesInstallOption -Options @{} -WithDocker

        $result.WithOllama | Should -BeFalse
        $result.WithDocker | Should -BeTrue
        $result.WithMLflow | Should -BeFalse
        $result.WithHindsight | Should -BeFalse
        $result.WithHermes | Should -BeFalse
    }

    It 'expands WithMLflow to its Ollama and Docker dependencies' {
        $result = Resolve-DotfilesInstallOption -Options @{} -WithMLflow

        $result.WithOllama | Should -BeTrue
        $result.WithDocker | Should -BeTrue
        $result.WithMLflow | Should -BeTrue
        $result.WithHindsight | Should -BeFalse
        $result.WithHermes | Should -BeFalse
    }

    It 'expands WithHindsight to MLflow and its runtime dependencies' {
        $result = Resolve-DotfilesInstallOption -Options @{} -WithHindsight

        $result.WithOllama | Should -BeTrue
        $result.WithDocker | Should -BeTrue
        $result.WithMLflow | Should -BeTrue
        $result.WithHindsight | Should -BeTrue
        $result.WithHermes | Should -BeFalse
    }

    It 'expands WithHermes to its complete desktop and runtime profile' {
        $result = Resolve-DotfilesInstallOption -Options @{} -WithHermes

        $result.WithOllama | Should -BeTrue
        $result.WithDocker | Should -BeTrue
        $result.WithMLflow | Should -BeTrue
        $result.WithHindsight | Should -BeTrue
        $result.WithHermes | Should -BeTrue
        $result.WithChrome | Should -BeTrue
        $result.WithDiscord | Should -BeTrue
        $result.WithChromium | Should -BeTrue
    }

    It 'preserves unrelated caller options' {
        $result = Resolve-DotfilesInstallOption -Options @{ SyncMarker = 'keep' } -WithOllama

        $result.SyncMarker | Should -Be 'keep'
    }
}
