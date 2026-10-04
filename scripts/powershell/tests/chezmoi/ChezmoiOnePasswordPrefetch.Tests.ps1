#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
    $script:prefetchLibrary = Join-Path $script:repoRoot 'scripts/powershell/lib/ChezmoiOnePasswordPrefetch.ps1'
    . $script:prefetchLibrary
}

Describe 'Windows chezmoi 1Password batch prefetch' {
    It 'generates the same SHA-256 environment name on Windows PowerShell 5.1 and PowerShell 7' {
        Get-ChezmoiSecretEnvironmentVariableName -Reference 'op://plane/item/credential' |
            Should -Be 'DOTFILES_OP_PREFETCHED_REF_e85e731df7e699a26941fa4707ad8300ee085570d303caf15b7a9777134e6b5e'
    }

    BeforeEach {
        $script:planeReference = 'op://plane/item/credential'
        $script:planeVariable = Get-ChezmoiSecretEnvironmentVariableName -Reference $script:planeReference
        Mock Get-ChezmoiPersonalAccount { 'personal-account-id' }
        Mock Get-ChezmoiOpReadTimeout { 180 }
        Mock Get-ChezmoiOpEnvironmentReference {
            @{ $script:planeReference = $script:planeVariable }
        }
        Mock Invoke-OpInjectManifest {
            [pscustomobject]@{
                ExitCode = 0
                Output = "DOTFILES_OP_PREFETCHED_KAGGLE_API_TOKEN=kaggle-token`nDOTFILES_OP_PREFETCHED_SSH_PUBLIC_KEY=ssh-ed25519 AAAA test`n$script:planeVariable=plane-token"
            }
        }
    }

    It 'collects secret references and invokes op inject once for the whole apply' {
        $result = Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe'

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-OpInjectManifest -Times 1 -ParameterFilter {
            $OpExe -eq 'op.exe' -and
            $Account -eq 'personal-account-id' -and
            $Manifest -match 'op://Private/Kaggle/' -and
            $Manifest -match 'op://Private/.+public key' -and
            $Manifest -match 'op://plane/item/credential' -and
            $Manifest -match 'op://Private/Kaggle/' -and
            $Manifest -match 'op://Private/.+public key'
        }
        $result.Secrets['DOTFILES_OP_PREFETCHED_KAGGLE_API_TOKEN'] | Should -Be 'kaggle-token'
        $result.Secrets[$script:planeVariable] | Should -Be 'plane-token'
        ($result.Secrets.Values -join "`n") | Should -Not -Match 'op://|token must not be written'
    }

    It 'does not invoke individual secret reads when the batch command fails' {
        Mock Invoke-OpInjectManifest { [pscustomobject]@{ ExitCode = 1; Output = 'private diagnostic' } }

        $result = Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe' 3>&1

        ($result | Out-String) | Should -Not -Match 'private diagnostic'
        $result.Secrets | Should -BeNullOrEmpty
        Should -Invoke Invoke-OpInjectManifest -Times 1
    }

    It 'reports when the batch command reaches its timeout' {
        Mock Invoke-OpInjectManifest {
            [pscustomobject]@{ ExitCode = 124; Output = ''; TimedOut = $true }
        }

        $messages = @(Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe' 3>&1)

        ($messages | Out-String) | Should -Match 'timed out after 180 seconds'
    }

    It 'reports delegated-session failures without exposing raw CLI diagnostics' {
        Mock Invoke-OpInjectManifest {
            [pscustomobject]@{
                ExitCode = 1
                Output = ''
                TimedOut = $false
                StandardError = 'cannot setup session: Failed to request delegated session for private diagnostic'
            }
        }

        $messages = @(Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe' 3>&1)

        ($messages | Out-String) | Should -Match 'delegated session'
        ($messages | Out-String) | Should -Not -Match 'private diagnostic'
    }

    It 'reports a sanitized summary for other batch errors' {
        Mock Invoke-OpInjectManifest {
            [pscustomobject]@{
                ExitCode = 1
                Output = ''
                TimedOut = $false
                StandardError = "could not read secret 'op://Private/Kaggle/credential': error initializing client: context deadline exceeded"
            }
        }

        $messages = @(Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe' 3>&1)

        ($messages | Out-String) | Should -Match 'request timed out'
        ($messages | Out-String) | Should -Not -Match 'op://Private/Kaggle/credential'
    }

    It 'classifies malformed or unsupported secret references without logging their URI' {
        Mock Invoke-OpInjectManifest {
            [pscustomobject]@{
                ExitCode = 1
                Output = ''
                TimedOut = $false
                StandardError = "invalid secret reference 'op://Private/item/public key': invalid character in secret reference"
            }
        }

        $messages = @(Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe' -OpExe 'op.exe' 3>&1)

        ($messages | Out-String) | Should -Match 'invalid or unsupported secret reference'
        ($messages | Out-String) | Should -Not -Match 'op://Private/item/public key'
    }

    It 'skips the batch command when the CLI is unavailable' {
        $result = Get-ChezmoiPrefetchResult -ChezmoiExe 'chezmoi.exe'
        $result.Success | Should -BeFalse
        $result.Secrets | Should -BeNullOrEmpty
        Should -Invoke Invoke-OpInjectManifest -Times 0
    }

    It 'uses the prefetched reference value in every Windows client template' {
        $templates = @(
            'chezmoi/dot_gemini/settings.json.tmpl',
            'chezmoi/dot_codex/config.toml.tmpl',
            'chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl'
        )

        foreach ($relativePath in $templates) {
            $content = Get-Content -LiteralPath (Join-Path $script:repoRoot $relativePath) -Raw
            $content | Should -Match 'DOTFILES_OP_PREFETCH_ENABLED' -Because $relativePath
            $content | Should -Match 'DOTFILES_OP_PREFETCHED_REF_%s' -Because $relativePath
            $content | Should -Match 'sha256sum' -Because $relativePath
        }
    }

    It 'uses the batched values in the Kaggle and SSH deploy scripts' {
        $kaggle = Get-Content -LiteralPath (Join-Path $script:repoRoot 'chezmoi/.chezmoiscripts/deploy/kaggle/run_always_deploy.ps1.tmpl') -Raw
        $ssh = Get-Content -LiteralPath (Join-Path $script:repoRoot 'chezmoi/.chezmoiscripts/deploy/ssh/run_always_deploy.ps1.tmpl') -Raw

        $kaggle | Should -Match 'DOTFILES_OP_PREFETCHED_KAGGLE_API_TOKEN'
        $ssh | Should -Match 'DOTFILES_OP_PREFETCHED_SSH_PUBLIC_KEY'
        $kaggle | Should -Match 'DOTFILES_OP_PREFETCH_ENABLED'
        $ssh | Should -Match 'DOTFILES_OP_PREFETCH_ENABLED'
    }
}

