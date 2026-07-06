#Requires -Module Pester

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
  $script:syncScriptPath = Join-Path $repoRoot 'scripts/powershell/sync-plane-github.ps1'
  $script:configTemplatePath = Join-Path $repoRoot 'chezmoi/dot_config/plane-github-sync/config.json.tmpl'

  if (Test-Path -LiteralPath $script:syncScriptPath) {
    . $script:syncScriptPath
  }
}

Describe 'Plane GitHub sync configuration' {
  It 'ships mappings for local project repositories' {
    Test-Path -LiteralPath $script:configTemplatePath | Should -BeTrue

    $content = Get-Content -LiteralPath $script:configTemplatePath -Raw
    $content | Should -Match 'rurusasu/dotfiles'
    $content | Should -Match 'rurusasu/article-collector'
    $content | Should -Match 'rurusasu/lifelog'
  }

  It 'uses the configured 1Password reference for the Plane API token' {
    Test-Path -LiteralPath $script:configTemplatePath | Should -BeTrue

    $content = Get-Content -LiteralPath $script:configTemplatePath -Raw
    $content | Should -Match 'op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/credential'
  }

  It 'uses the configured local Plane workspace slug without a placeholder' {
    Test-Path -LiteralPath $script:configTemplatePath | Should -BeTrue

    $content = Get-Content -LiteralPath $script:configTemplatePath -Raw
    $content | Should -Match '"planeWorkspaceSlug":\s+"ruru"'
    $content | Should -Not -Match '\$\{PLANE_WORKSPACE_SLUG\}'
  }
}

Describe 'Plane GitHub sync state' {
  It 'uses state.json next to the config when statePath is not configured' {
    $configPath = Join-Path $TestDrive 'plane-github-sync.json'
    '{"planeBaseUrl":"http://127.0.0.1:18080","planeWorkspaceSlug":"team","planeApiToken":"test","projectMappings":[]}' |
      Set-Content -LiteralPath $configPath -Encoding UTF8

    $config = Get-PlaneGithubSyncConfig -Path $configPath

    Get-PlaneGithubSyncStatePath -Config $config -ConfigPath $configPath |
      Should -Be (Join-Path $TestDrive 'state.json')
  }

  It 'uses a relative state.json path when config path has no parent directory' {
    $config = [pscustomobject]@{}

    Get-PlaneGithubSyncStatePath -Config $config -ConfigPath 'config.json' |
      Should -Be 'state.json'
  }

  It 'uses configured relative statePath as-is' {
    $config = [pscustomobject]@{
      statePath = 'custom/state.json'
    }

    Get-PlaneGithubSyncStatePath -Config $config -ConfigPath (Join-Path $TestDrive 'plane-github-sync.json') |
      Should -Be 'custom/state.json'
  }

  It 'expands embedded environment variables in configured statePath' {
    $previousStateDir = [Environment]::GetEnvironmentVariable('PG_TEST_STATE_DIR')
    try {
      $stateDir = Join-Path $TestDrive 'configured-state'
      [Environment]::SetEnvironmentVariable('PG_TEST_STATE_DIR', $stateDir)
      $config = [pscustomobject]@{
        statePath = '${PG_TEST_STATE_DIR}/state.json'
      }

      Get-PlaneGithubSyncStatePath -Config $config -ConfigPath (Join-Path $TestDrive 'plane-github-sync.json') |
        Should -Be "$stateDir/state.json"
    } finally {
      [Environment]::SetEnvironmentVariable('PG_TEST_STATE_DIR', $previousStateDir)
    }
  }

  It 'loads an empty sync state when the state file does not exist' {
    $state = Get-PlaneGithubSyncState -Path (Join-Path $TestDrive 'missing-state.json')

    $state.links.PSObject.Properties | Should -HaveCount 0
  }

  It 'saves and reloads sync state links' {
    $statePath = Join-Path $TestDrive 'state.json'
    $state = New-PlaneGithubSyncState
    Set-PlaneGithubSyncStateLink -State $state -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/12' -Value @{
      repository = 'rurusasu/dotfiles'
      githubIssueUrl = 'https://github.com/rurusasu/dotfiles/issues/12'
      githubFingerprint = 'github-fp'
      planeFingerprint = 'plane-fp'
      planeWorkItemId = 'work-item-1'
    }

    Save-PlaneGithubSyncState -State $state -Path $statePath
    $loaded = Get-PlaneGithubSyncState -Path $statePath

    (Get-PlaneGithubSyncStateLink -State $loaded -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/12').planeFingerprint |
      Should -Be 'plane-fp'
  }

  It 'creates literal parent directories when saving sync state' {
    $statePath = Join-Path (Join-Path $TestDrive 'state[1]') 'state.json'

    Save-PlaneGithubSyncState -State (New-PlaneGithubSyncState) -Path $statePath

    Test-Path -LiteralPath $statePath | Should -BeTrue
  }

  It 'builds different fingerprints when title, body, or state changes' {
    $first = New-PlaneGithubFingerprint -Title 'Fix installer' -Body 'Body' -Closed $false
    $second = New-PlaneGithubFingerprint -Title 'Fix installer now' -Body 'Body' -Closed $false
    $third = New-PlaneGithubFingerprint -Title 'Fix installer' -Body 'Body changed' -Closed $false
    $fourth = New-PlaneGithubFingerprint -Title 'Fix installer' -Body 'Body' -Closed $true

    $first | Should -Not -Be $second
    $first | Should -Not -Be $third
    $first | Should -Not -Be $fourth
  }

  It 'builds deterministic lowercase SHA256 fingerprints' {
    $first = New-PlaneGithubFingerprint -Title 'Fix installer' -Body 'Body' -Closed $false
    $second = New-PlaneGithubFingerprint -Title 'Fix installer' -Body 'Body' -Closed $false

    $first | Should -Be $second
    $first | Should -Match '^[0-9a-f]{64}$'
  }
}

Describe 'GitHub issue helpers' {
  BeforeEach {
    $global:PlaneGithubTestGhArgs = @()
    $global:PlaneGithubTestGhOutput = @()
    $global:PlaneGithubTestGhExitCode = 0
    $global:LASTEXITCODE = 0

    function global:gh {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Arguments
      )

      $global:PlaneGithubTestGhArgs = @($Arguments)
      $global:LASTEXITCODE = $global:PlaneGithubTestGhExitCode
      return $global:PlaneGithubTestGhOutput
    }
  }

  AfterEach {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    Remove-Variable -Name PlaneGithubTestGhArgs -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PlaneGithubTestGhOutput -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PlaneGithubTestGhExitCode -Scope Global -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
  }

  It 'lists GitHub issues from slurped paginated output' {
    $global:PlaneGithubTestGhOutput = '[[{"number":1,"html_url":"https://github.com/rurusasu/dotfiles/issues/1"}],[{"number":2,"html_url":"https://github.com/rurusasu/dotfiles/issues/2"}]]'

    $issues = @(Invoke-GitHubIssueList -Repository 'rurusasu/dotfiles')

    ($global:PlaneGithubTestGhArgs -join '|') | Should -Be 'api|repos/rurusasu/dotfiles/issues|--method|GET|-f|state=all|--paginate|--slurp'
    $issues | Should -HaveCount 2
    $issues[0].PSObject.Properties['number'].Value | Should -Be 1
    $issues[1].PSObject.Properties['number'].Value | Should -Be 2
  }

  It 'returns no GitHub issues when list output is empty' {
    $global:PlaneGithubTestGhOutput = @()

    @(Invoke-GitHubIssueList -Repository 'rurusasu/dotfiles') | Should -HaveCount 0
  }

  It 'throws when listing GitHub issues fails' {
    $global:PlaneGithubTestGhExitCode = 1

    { Invoke-GitHubIssueList -Repository 'rurusasu/dotfiles' } |
      Should -Throw -ExpectedMessage '*Failed to list GitHub issues in rurusasu/dotfiles*'
  }

  It 'filters pull requests returned by GitHub issues' {
    $issue = [pscustomobject]@{ number = 1; html_url = 'https://github.com/rurusasu/dotfiles/issues/1' }
    $pullRequest = [pscustomobject]@{
      number = 2
      html_url = 'https://github.com/rurusasu/dotfiles/pull/2'
      pull_request = [pscustomobject]@{ url = 'https://api.github.com/repos/rurusasu/dotfiles/pulls/2' }
    }

    @(Get-GitHubSyncableIssues -Issues @($issue, $pullRequest)).number | Should -Be 1
  }

  It 'returns no syncable GitHub issues when input is null' {
    @(Get-GitHubSyncableIssues -Issues $null) | Should -HaveCount 0
  }

  It 'patches a GitHub issue with title, body, and state' {
    $global:PlaneGithubTestGhOutput = '{"html_url":"https://github.com/rurusasu/dotfiles/issues/12","state":"closed"}'

    $issue = Invoke-GitHubIssuePatch -Repository 'rurusasu/dotfiles' -Number 12 -Title 'Plane title' -Body 'Plane body' -State 'closed'

    ($global:PlaneGithubTestGhArgs -join '|') | Should -Be 'api|repos/rurusasu/dotfiles/issues/12|--method|PATCH|-f|state=closed|-f|title=Plane title|-f|body=Plane body'
    $issue.html_url | Should -Be 'https://github.com/rurusasu/dotfiles/issues/12'
    $issue.state | Should -Be 'closed'
  }

  It 'returns an empty object when patch output is empty' {
    $global:PlaneGithubTestGhOutput = @()

    $issue = Invoke-GitHubIssuePatch -Repository 'rurusasu/dotfiles' -Number 12 -State 'open' -Title '' -Body $null

    ($global:PlaneGithubTestGhArgs -join '|') | Should -Be 'api|repos/rurusasu/dotfiles/issues/12|--method|PATCH|-f|state=open'
    $issue.PSObject.Properties | Should -HaveCount 0
  }

  It 'throws when patching a GitHub issue fails' {
    $global:PlaneGithubTestGhExitCode = 1

    { Invoke-GitHubIssuePatch -Repository 'rurusasu/dotfiles' -Number 12 -State 'open' } |
      Should -Throw -ExpectedMessage '*Failed to update GitHub issue #12 in rurusasu/dotfiles*'
  }

  It 'maps Plane fields to a closed GitHub issue update' {
    $script:githubUpdate = $null
    Mock Invoke-GitHubIssuePatch {
      $script:githubUpdate = @{
        Repository = $Repository
        Number = $Number
        Title = $Title
        Body = $Body
        State = $State
      }
      return [pscustomobject]@{ html_url = "https://github.com/$Repository/issues/$Number"; state = $State }
    }

    Update-GitHubIssueFromPlane -Repository 'rurusasu/dotfiles' -IssueNumber 12 -Title 'Plane title' -Body 'Plane body' -Closed $true

    $script:githubUpdate.Repository | Should -Be 'rurusasu/dotfiles'
    $script:githubUpdate.Number | Should -Be 12
    $script:githubUpdate.Title | Should -Be 'Plane title'
    $script:githubUpdate.Body | Should -Match 'Plane body'
    $script:githubUpdate.State | Should -Be 'closed'
  }

  It 'extracts issue numbers from GitHub issue URLs' {
    Get-GitHubIssueNumberFromUrl -Url 'https://github.com/rurusasu/dotfiles/issues/77' |
      Should -Be 77
    Get-GitHubIssueNumberFromUrl -Url 'https://github.com/rurusasu/dotfiles/pull/77' |
      Should -Be 0
  }

  It 'builds the same identity key for GitHub API and web issue URLs' {
    Get-GitHubIssueIdentityKey -Repository 'rurusasu/dotfiles' -Url 'https://api.github.com/repos/rurusasu/dotfiles/issues/44' |
      Should -Be 'rurusasu/dotfiles#44'
    Get-GitHubIssueIdentityKey -Repository 'rurusasu/dotfiles' -Url 'https://github.com/rurusasu/dotfiles/issues/44/' |
      Should -Be 'rurusasu/dotfiles#44'
  }

  It 'rejects GitHub issue identity keys for other repositories' {
    Get-GitHubIssueIdentityKey -Repository 'rurusasu/dotfiles' -Url 'https://github.com/other/repo/issues/44' |
      Should -Be ''
    Get-GitHubIssueIdentityKey -Repository 'rurusasu/dotfiles' -Url 'https://api.github.com/repos/other/repo/issues/44' |
      Should -Be ''
    Get-GitHubIssueIdentityKeyFromText -Repository 'rurusasu/dotfiles' -Text 'https://github.com/other/repo/issues/44' |
      Should -Be ''
  }
}

Describe 'Plane work item helpers' {
  It 'selects completed and open Plane states by group' {
    $states = @(
      [pscustomobject]@{ id = 'state-backlog'; name = 'Backlog'; group = 'backlog' },
      [pscustomobject]@{ id = 'state-done'; name = 'Done'; group = 'completed' },
      [pscustomobject]@{ id = 'state-cancel'; name = 'Cancelled'; group = 'cancelled' }
    )

    (Find-PlaneStateForGitHubState -States $states -GitHubState 'closed').id | Should -Be 'state-done'
    (Find-PlaneStateForGitHubState -States $states -GitHubState 'open').id | Should -Be 'state-backlog'
  }

  It 'prefers unstarted before backlog before started for open GitHub issues' {
    $states = @(
      [pscustomobject]@{ id = 'state-started'; name = 'Started'; group = 'started' },
      [pscustomobject]@{ id = 'state-backlog'; name = 'Backlog'; group = 'backlog' },
      [pscustomobject]@{ id = 'state-unstarted'; name = 'Unstarted'; group = 'unstarted' }
    )
    $withoutUnstarted = @($states[0], $states[1])
    $onlyStarted = @($states[0])

    (Find-PlaneStateForGitHubState -States $states -GitHubState 'open').id | Should -Be 'state-unstarted'
    (Find-PlaneStateForGitHubState -States $withoutUnstarted -GitHubState 'open').id | Should -Be 'state-backlog'
    (Find-PlaneStateForGitHubState -States $onlyStarted -GitHubState 'open').id | Should -Be 'state-started'
  }

  It 'does not allow Plane API Put requests for work item sync' {
    $config = [pscustomobject]@{ planeBaseUrl = 'http://127.0.0.1:18080'; planeWorkspaceSlug = 'team' }

    { Invoke-PlaneApi -Method 'Put' -Config $config -Token 'token' -Path 'projects/project-1/work-items/' } |
      Should -Throw -ExpectedMessage "*Cannot validate argument on parameter 'Method'*"
  }

  It 'reads every page from Plane API cursor collections' {
    $config = [pscustomobject]@{ planeBaseUrl = 'http://127.0.0.1:18080'; planeWorkspaceSlug = 'team' }
    $script:planeCollectionPaths = @()

    Mock Invoke-PlaneApi {
      $script:planeCollectionPaths += $Path
      if ($Path -eq 'projects/project-1/work-items/') {
        return [pscustomobject]@{
          results = @([pscustomobject]@{ id = 'work-item-1' })
          next_page_results = $true
          next_cursor = 'cursor 1'
        }
      }

      if ($Path -eq 'projects/project-1/work-items/?cursor=cursor%201') {
        return [pscustomobject]@{
          results = @([pscustomobject]@{ id = 'work-item-2' })
          next_page_results = $false
          next_cursor = $null
        }
      }

      throw "Unexpected Plane API call: $Method $Path"
    }

    $items = Get-PlaneApiCollection -Config $config -Token 'token' -Path 'projects/project-1/work-items/'

    $items.Count | Should -Be 2
    $items[0].id | Should -Be 'work-item-1'
    $items[1].id | Should -Be 'work-item-2'
    $script:planeCollectionPaths[0] | Should -Be 'projects/project-1/work-items/'
    $script:planeCollectionPaths[1] | Should -Be 'projects/project-1/work-items/?cursor=cursor%201'
  }

  It 'creates a GitHub issue in Plane with external identity' {
    $script:planeCreate = $null
    $config = [pscustomobject]@{ planeBaseUrl = 'http://127.0.0.1:18080'; planeWorkspaceSlug = 'team' }
    $project = [pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT' }
    $issue = [pscustomobject]@{
      number = 55
      title = 'GitHub title'
      body = "GitHub body <tag> & details"
      state = 'closed'
      html_url = 'https://github.com/rurusasu/dotfiles/issues/55'
    }
    $states = @([pscustomobject]@{ id = 'state-done'; group = 'completed' })

    Mock Invoke-PlaneApi {
      $script:planeCreate = @{
        Method = $Method
        Path = $Path
        Body = $Body
      }
      return [pscustomobject]@{ id = 'work-item-55'; external_id = $Body.external_id }
    }

    New-PlaneWorkItemFromGitHubIssue -Config $config -Token 'token' -Project $project -Issue $issue -States $states

    $script:planeCreate.Method | Should -Be 'Post'
    $script:planeCreate.Path | Should -Be 'projects/project-1/work-items/'
    $script:planeCreate.Body.name | Should -Be 'GitHub title'
    $script:planeCreate.Body.description_html | Should -Match 'GitHub body &lt;tag&gt; &amp; details'
    $script:planeCreate.Body.description_html | Should -Match '<a href="https://github\.com/rurusasu/dotfiles/issues/55">https://github\.com/rurusasu/dotfiles/issues/55</a>'
    $script:planeCreate.Body.description_html | Should -Match 'plane-github-sync: github-issue=https://github\.com/rurusasu/dotfiles/issues/55'
    $script:planeCreate.Body.external_source | Should -Be 'github'
    $script:planeCreate.Body.external_id | Should -Be 'https://github.com/rurusasu/dotfiles/issues/55'
    $script:planeCreate.Body.state | Should -Be 'state-done'
  }

  It 'returns a GitHub external id only for GitHub-linked Plane work items' {
    Get-PlaneWorkItemGitHubIssueUrl -WorkItem ([pscustomobject]@{
      external_source = 'github'
      external_id = 'https://github.com/rurusasu/dotfiles/issues/77'
    }) | Should -Be 'https://github.com/rurusasu/dotfiles/issues/77'

    Get-PlaneWorkItemGitHubIssueUrl -WorkItem ([pscustomobject]@{
      external_source = 'slack'
      external_id = 'https://github.com/rurusasu/dotfiles/issues/77'
    }) | Should -Be ''
  }

  It 'treats completed and cancelled Plane state groups as closed' {
    $states = @(
      [pscustomobject]@{ id = 'state-backlog'; group = 'backlog' },
      [pscustomobject]@{ id = 'state-done'; group = 'completed' },
      [pscustomobject]@{ id = 'state-cancelled'; group = 'cancelled' }
    )

    Test-PlaneWorkItemClosed -WorkItem ([pscustomobject]@{ state = 'state-done' }) -States $states |
      Should -BeTrue
    Test-PlaneWorkItemClosed -WorkItem ([pscustomobject]@{ state = 'state-cancelled' }) -States $states |
      Should -BeTrue
    Test-PlaneWorkItemClosed -WorkItem ([pscustomobject]@{ state = 'state-backlog' }) -States $states |
      Should -BeFalse
  }

  It 'patches a Plane work item from a GitHub issue' {
    $script:planePatch = $null
    $config = [pscustomobject]@{ planeBaseUrl = 'http://127.0.0.1:18080'; planeWorkspaceSlug = 'team' }
    $project = [pscustomobject]@{ id = 'project-1'; name = 'dotfiles' }
    $workItem = [pscustomobject]@{ id = 'work-item-77' }
    $issue = [pscustomobject]@{
      title = 'GitHub title'
      body = 'GitHub body'
      state = 'closed'
      html_url = 'https://github.com/rurusasu/dotfiles/issues/77'
    }
    $states = @([pscustomobject]@{ id = 'state-done'; group = 'completed' })

    Mock Invoke-PlaneApi {
      $script:planePatch = @{
        Method = $Method
        Path = $Path
        Body = $Body
      }
      return [pscustomobject]@{ id = 'work-item-77' }
    }

    Update-PlaneWorkItemFromGitHubIssue -Config $config -Token 'token' -Project $project -WorkItem $workItem -Issue $issue -States $states

    $script:planePatch.Method | Should -Be 'Patch'
    $script:planePatch.Path | Should -Be 'projects/project-1/work-items/work-item-77/'
    $script:planePatch.Body.name | Should -Be 'GitHub title'
    $script:planePatch.Body.description_html | Should -Match 'GitHub body'
    $script:planePatch.Body.external_source | Should -Be 'github'
    $script:planePatch.Body.external_id | Should -Be 'https://github.com/rurusasu/dotfiles/issues/77'
    $script:planePatch.Body.state | Should -Be 'state-done'
  }
}

Describe 'Invoke-PlaneGithubSync' {
  BeforeEach {
    if (-not (Test-Path -LiteralPath $script:syncScriptPath)) {
      throw "Missing sync script: $script:syncScriptPath"
    }

    $script:planeUpdateBody = $null
    $script:createdIssueArgs = $null
    $script:testConfigPath = Join-Path $TestDrive 'plane-github-sync.json'
    @'
{
  "planeBaseUrl": "http://127.0.0.1:18080",
  "planeWorkspaceSlug": "team",
  "planeApiToken": "test-token",
  "projectMappings": [
    {
      "planeProject": "dotfiles",
      "githubRepository": "rurusasu/dotfiles"
    }
  ]
}
'@ | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8
  }

  It 'creates a GitHub issue for an unlinked Plane work item and writes the link back' {
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @(
          [pscustomobject]@{
            id = 'project-1'
            name = 'dotfiles'
            identifier = 'DOT'
            slug = 'dotfiles'
          }
        )
      }

      if ($Path -eq 'projects/project-1/work-items/') {
        return @(
          [pscustomobject]@{
            id = 'work-item-1'
            name = 'Fix installer'
            sequence_id = 12
            description_html = '<p>Make install.cmd robust.</p>'
          }
        )
      }

      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }

      if ($Method -eq 'Patch') {
        $script:planeUpdateBody = $Body
        return [pscustomobject]@{ ok = $true }
      }

      throw "Unexpected Plane API call: $Method $Path"
    }

    Mock Invoke-GitHubIssueCreate {
      $script:createdIssueArgs = @{
        Repository = $Repository
        Title = $Title
        Body = $Body
      }

      return 'https://github.com/rurusasu/dotfiles/issues/123'
    }
    Mock Invoke-GitHubIssueList {
      return @()
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Invoke-GitHubIssueCreate -Times 1 -Exactly
    $script:createdIssueArgs.Repository | Should -Be 'rurusasu/dotfiles'
    $script:createdIssueArgs.Title | Should -Be 'Fix installer'
    $script:createdIssueArgs.Body | Should -Match 'work-item-1'
    $script:planeUpdateBody.description_html | Should -Match 'https://github.com/rurusasu/dotfiles/issues/123'
  }

  It 'saves the post-link Plane fingerprint after creating a GitHub issue' {
    $statePath = Join-Path $TestDrive 'state-plane-create-fingerprint.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    $script:createdIssueArgs = $null
    $descriptionHtml = '<p>Make install.cmd robust.</p>'
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-1'
          name = 'Fix installer'
          sequence_id = 12
          description_html = $descriptionHtml
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch') {
        return [pscustomobject]@{ ok = $true }
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @()
    }
    Mock Invoke-GitHubIssueCreate {
      $script:createdIssueArgs = @{
        Repository = $Repository
        Title = $Title
        Body = $Body
      }
      return 'https://github.com/rurusasu/dotfiles/issues/123'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    $saved = Get-PlaneGithubSyncState -Path $statePath
    $link = Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/123'
    $postLinkDescription = Add-GitHubLinkToPlaneDescription -DescriptionHtml $descriptionHtml -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/123'
    $expectedPlaneFingerprint = New-PlaneGithubFingerprint -Title 'Fix installer' -Body (Get-PlainTextFromHtml -Html $postLinkDescription) -Closed $false
    $preLinkFingerprint = New-PlaneGithubFingerprint -Title 'Fix installer' -Body (Get-PlainTextFromHtml -Html $descriptionHtml) -Closed $false
    $expectedGitHubFingerprint = New-PlaneGithubFingerprint -Title 'Fix installer' -Body $script:createdIssueArgs.Body -Closed $false

    $link.planeFingerprint | Should -Be $expectedPlaneFingerprint
    $link.planeFingerprint | Should -Not -Be $preLinkFingerprint
    $link.githubFingerprint | Should -Be $expectedGitHubFingerprint
  }

  It 'closes a GitHub issue created from an already closed Plane work item' {
    $statePath = Join-Path $TestDrive 'state-plane-create-closed.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    $script:closedIssueUpdate = $null
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-1'
          name = 'Done in Plane'
          sequence_id = 12
          state = 'state-done'
          description_html = '<p>Finished before sync.</p>'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-done'; group = 'completed' })
      }
      if ($Method -eq 'Patch') {
        return [pscustomobject]@{ ok = $true }
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @()
    }
    Mock Invoke-GitHubIssueCreate {
      return 'https://github.com/rurusasu/dotfiles/issues/123'
    }
    Mock Update-GitHubIssueFromPlane {
      $script:closedIssueUpdate = @{
        Repository = $Repository
        IssueNumber = $IssueNumber
        Title = $Title
        Body = $Body
        Closed = $Closed
      }
      return [pscustomobject]@{ state = 'closed' }
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Update-GitHubIssueFromPlane -Times 1 -Exactly
    $script:closedIssueUpdate.Repository | Should -Be 'rurusasu/dotfiles'
    $script:closedIssueUpdate.IssueNumber | Should -Be 123
    $script:closedIssueUpdate.Closed | Should -BeTrue

    $saved = Get-PlaneGithubSyncState -Path $statePath
    $link = Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/123'
    $expectedGitHubFingerprint = New-PlaneGithubFingerprint -Title 'Done in Plane' -Body $script:closedIssueUpdate.Body -Closed $true
    $link.githubFingerprint | Should -Be $expectedGitHubFingerprint
  }

  It 'links an unlinked Plane work item to an existing GitHub issue with the same sync marker' {
    $statePath = Join-Path $TestDrive 'state-recovered-create.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    $script:planeRecoveredLinkBody = $null
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-1'
          name = 'Fix installer'
          description_html = '<p>Make install.cmd robust.</p>'
          state = 'state-backlog'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch' -and $Path -eq 'projects/project-1/work-items/work-item-1/') {
        $script:planeRecoveredLinkBody = $Body
        return [pscustomobject]@{ ok = $true }
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 123
        title = 'Fix installer'
        body = "Synced from Plane work item.`n`n<!-- plane-github-sync: workspace=team; project_id=project-1; work_item_id=work-item-1 -->"
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/123'
      })
    }
    Mock Invoke-GitHubIssueCreate {
      throw 'GitHub issue should not be duplicated when marker already exists'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Invoke-GitHubIssueCreate -Times 0 -Exactly
    $script:planeRecoveredLinkBody.external_id | Should -Be 'https://github.com/rurusasu/dotfiles/issues/123'
    $saved = Get-PlaneGithubSyncState -Path $statePath
    (Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/123').planeWorkItemId |
      Should -Be 'work-item-1'
  }

  It 'creates a Plane work item for a GitHub issue that is not in Plane' {
    $script:createdPlaneIssue = $null
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @()
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 77
        title = 'From GitHub'
        body = 'Issue body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/77'
      })
    }
    Mock New-PlaneWorkItemFromGitHubIssue {
      $script:createdPlaneIssue = $Issue
      return [pscustomobject]@{ id = 'work-item-77'; external_id = $Issue.html_url }
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    $script:createdPlaneIssue.html_url | Should -Be 'https://github.com/rurusasu/dotfiles/issues/77'
  }

  It 'updates GitHub when only the linked Plane work item changed' {
    $script:githubUpdateFromPlane = $null
    $statePath = Join-Path $TestDrive 'state-plane-only.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    $oldGitHubBody = "Old body`n`n<!-- plane-github-sync: workspace=team; project_id=project-1; work_item_id=work-item-12 -->"
    $oldPlaneFingerprint = New-PlaneGithubFingerprint -Title 'Old title' -Body 'Old body' -Closed $false
    $oldGitHubFingerprint = New-PlaneGithubFingerprint -Title 'Old title' -Body $oldGitHubBody -Closed $false
    $state = New-PlaneGithubSyncState
    Set-PlaneGithubSyncStateLink -State $state -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/12' -Value @{
      repository = 'rurusasu/dotfiles'
      githubIssueUrl = 'https://github.com/rurusasu/dotfiles/issues/12'
      githubIssueNumber = 12
      planeProjectId = 'project-1'
      planeWorkItemId = 'work-item-12'
      planeFingerprint = $oldPlaneFingerprint
      githubFingerprint = $oldGitHubFingerprint
    }
    Save-PlaneGithubSyncState -State $state -Path $statePath

    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-12'
          name = 'New Plane title'
          description_html = '<p>New Plane body</p>'
          state = 'state-backlog'
          external_source = 'github'
          external_id = 'https://github.com/rurusasu/dotfiles/issues/12'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 12
        title = 'Old title'
        body = $oldGitHubBody
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/12'
      })
    }
    Mock Update-GitHubIssueFromPlane {
      $script:githubUpdateFromPlane = @{
        Repository = $Repository
        IssueNumber = $IssueNumber
        Title = $Title
        Body = $Body
        Closed = $Closed
      }
      return [pscustomobject]@{ html_url = "https://github.com/$Repository/issues/$IssueNumber" }
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    $script:githubUpdateFromPlane.Repository | Should -Be 'rurusasu/dotfiles'
    $script:githubUpdateFromPlane.IssueNumber | Should -Be 12
    $script:githubUpdateFromPlane.Title | Should -Be 'New Plane title'
    $script:githubUpdateFromPlane.Body | Should -Match '^New Plane body'
    $script:githubUpdateFromPlane.Body | Should -Match 'plane-github-sync: workspace=team; project_id=project-1; work_item_id=work-item-12'
    $script:githubUpdateFromPlane.Closed | Should -BeFalse
  }

  It 'updates Plane from GitHub when both linked sides changed' {
    $script:planeConflictPatchBody = $null
    $statePath = Join-Path $TestDrive 'state-conflict.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    $oldFingerprint = New-PlaneGithubFingerprint -Title 'Old title' -Body 'Old body' -Closed $false
    $state = New-PlaneGithubSyncState
    Set-PlaneGithubSyncStateLink -State $state -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/33' -Value @{
      repository = 'rurusasu/dotfiles'
      githubIssueUrl = 'https://github.com/rurusasu/dotfiles/issues/33'
      githubIssueNumber = 33
      planeProjectId = 'project-1'
      planeWorkItemId = 'work-item-33'
      planeFingerprint = $oldFingerprint
      githubFingerprint = $oldFingerprint
    }
    Save-PlaneGithubSyncState -State $state -Path $statePath

    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-33'
          name = 'Plane changed title'
          description_html = '<p>Plane changed body</p>'
          state = 'state-backlog'
          external_source = 'github'
          external_id = 'https://github.com/rurusasu/dotfiles/issues/33'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @(
          [pscustomobject]@{ id = 'state-backlog'; group = 'backlog' },
          [pscustomobject]@{ id = 'state-done'; group = 'completed' }
        )
      }
      if ($Method -eq 'Patch' -and $Path -eq 'projects/project-1/work-items/work-item-33/') {
        $script:planeConflictPatchBody = $Body
        return [pscustomobject]@{ id = 'work-item-33' }
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 33
        title = 'GitHub changed title'
        body = 'GitHub changed body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/33'
      })
    }
    Mock Update-GitHubIssueFromPlane {
      throw 'GitHub should not be updated when both sides changed'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    $script:planeConflictPatchBody.name | Should -Be 'GitHub changed title'
    $script:planeConflictPatchBody.description_html | Should -Match 'GitHub changed body'
    $script:planeConflictPatchBody.external_id | Should -Be 'https://github.com/rurusasu/dotfiles/issues/33'
  }

  It 'records a baseline without mutating either side when state is missing for an existing link' {
    $statePath = Join-Path $TestDrive 'state-missing-baseline.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-22'
          name = 'Plane title'
          description_html = '<p>Plane body</p>'
          state = 'state-backlog'
          external_source = 'github'
          external_id = 'https://github.com/rurusasu/dotfiles/issues/22'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch') {
        throw 'Plane should not be patched when missing state is baselined'
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 22
        title = 'GitHub title'
        body = 'GitHub body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/22'
      })
    }
    Mock Update-GitHubIssueFromPlane {
      throw 'GitHub should not be patched when missing state is baselined'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Update-GitHubIssueFromPlane -Times 0 -Exactly
    $saved = Get-PlaneGithubSyncState -Path $statePath
    $link = Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/22'
    $link.planeWorkItemId | Should -Be 'work-item-22'
    $link.githubIssueNumber | Should -Be 22
  }

  It 'matches linked issues by repository and number when Plane stores the GitHub API issue URL' {
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-44'
          name = 'Plane title'
          description_html = '<p>Plane body</p>'
          state = 'state-backlog'
          external_source = 'github'
          external_id = 'https://api.github.com/repos/rurusasu/dotfiles/issues/44'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch') {
        throw 'Plane should not be patched for a normalized existing link baseline'
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 44
        title = 'GitHub title'
        body = 'GitHub body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/44'
      })
    }
    Mock New-PlaneWorkItemFromGitHubIssue {
      throw 'Plane work item should not be created for normalized existing link'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke New-PlaneWorkItemFromGitHubIssue -Times 0 -Exactly
  }

  It 'records a baseline for a description-linked Plane work item when state is missing' {
    $statePath = Join-Path $TestDrive 'state-description-linked-baseline.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-9'
          name = 'Description linked Plane title'
          description_html = '<p>GitHub Issue: https://github.com/rurusasu/dotfiles/issues/9</p>'
          state = 'state-backlog'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch') {
        throw 'Plane should not be patched for a description-only baseline'
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 9
        title = 'GitHub title'
        body = 'GitHub body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/9'
      })
    }
    Mock Invoke-GitHubIssueCreate {
      throw 'GitHub issue should not be created for a description-linked work item'
    }
    Mock New-PlaneWorkItemFromGitHubIssue {
      throw 'Plane work item should not be created for a description-linked GitHub issue'
    }
    Mock Update-GitHubIssueFromPlane {
      throw 'GitHub should not be patched for a description-only baseline'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Invoke-GitHubIssueCreate -Times 0 -Exactly
    Should -Invoke New-PlaneWorkItemFromGitHubIssue -Times 0 -Exactly
    Should -Invoke Update-GitHubIssueFromPlane -Times 0 -Exactly
    $saved = Get-PlaneGithubSyncState -Path $statePath
    $link = Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/9'
    $link.planeWorkItemId | Should -Be 'work-item-9'
    $link.githubIssueNumber | Should -Be 9
  }

  It 'matches description-linked issues by repository and number when Plane stores the GitHub API issue URL' {
    $statePath = Join-Path $TestDrive 'state-description-api-url.json'
    @{
      planeBaseUrl = 'http://127.0.0.1:18080'
      planeWorkspaceSlug = 'team'
      planeApiToken = 'test-token'
      statePath = $statePath
      projectMappings = @(@{
        planeProject = 'dotfiles'
        githubRepository = 'rurusasu/dotfiles'
      })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:testConfigPath -Encoding UTF8

    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @([pscustomobject]@{ id = 'project-1'; name = 'dotfiles'; identifier = 'DOT'; slug = 'dotfiles' })
      }
      if ($Path -eq 'projects/project-1/work-items/') {
        return @([pscustomobject]@{
          id = 'work-item-44'
          name = 'Description API linked Plane title'
          description_html = '<p>GitHub Issue: https://api.github.com/repos/rurusasu/dotfiles/issues/44</p>'
          state = 'state-backlog'
        })
      }
      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }
      if ($Method -eq 'Patch') {
        throw 'Plane should not be patched for a normalized description-only baseline'
      }
      throw "Unexpected Plane API call: $Method $Path"
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 44
        title = 'GitHub title'
        body = 'GitHub body'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/44'
      })
    }
    Mock Invoke-GitHubIssueCreate {
      throw 'GitHub issue should not be created for a normalized description-linked work item'
    }
    Mock New-PlaneWorkItemFromGitHubIssue {
      throw 'Plane work item should not be created for a normalized description-linked GitHub issue'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Invoke-GitHubIssueCreate -Times 0 -Exactly
    Should -Invoke New-PlaneWorkItemFromGitHubIssue -Times 0 -Exactly
    $saved = Get-PlaneGithubSyncState -Path $statePath
    $link = Get-PlaneGithubSyncStateLink -State $saved -Repository 'rurusasu/dotfiles' -GitHubIssueUrl 'https://github.com/rurusasu/dotfiles/issues/44'
    $link.planeWorkItemId | Should -Be 'work-item-44'
    $link.githubIssueNumber | Should -Be 44
  }

  It 'skips a Plane work item that already has a GitHub issue link' {
    Mock Invoke-PlaneApi {
      if ($Path -eq 'projects/') {
        return @(
          [pscustomobject]@{
            id = 'project-1'
            name = 'dotfiles'
            identifier = 'DOT'
            slug = 'dotfiles'
          }
        )
      }

      if ($Path -eq 'projects/project-1/work-items/') {
        return @(
          [pscustomobject]@{
            id = 'work-item-1'
            name = 'Fix installer'
            sequence_id = 12
            description_html = '<p>GitHub Issue: https://github.com/rurusasu/dotfiles/issues/9</p>'
          }
        )
      }

      if ($Path -eq 'projects/project-1/states/') {
        return @([pscustomobject]@{ id = 'state-backlog'; group = 'backlog' })
      }

      throw "Unexpected Plane API call: $Method $Path"
    }

    Mock Invoke-GitHubIssueCreate {
      throw 'GitHub issue should not be created for already linked work item'
    }
    Mock Invoke-GitHubIssueList {
      return @([pscustomobject]@{
        number = 9
        title = 'Existing GitHub issue'
        body = 'Already linked from Plane'
        state = 'open'
        html_url = 'https://github.com/rurusasu/dotfiles/issues/9'
      })
    }
    Mock New-PlaneWorkItemFromGitHubIssue {
      throw 'Plane work item should not be created for already linked GitHub issue'
    }

    Invoke-PlaneGithubSync -ConfigPath $script:testConfigPath

    Should -Invoke Invoke-GitHubIssueCreate -Times 0 -Exactly
    Should -Invoke New-PlaneWorkItemFromGitHubIssue -Times 0 -Exactly
  }

  It 'matches Plane projects by identifier, slug, or name' {
    $mapping = [pscustomobject]@{
      planeProject = 'lifelog'
      githubRepository = 'rurusasu/lifelog'
    }
    $project = [pscustomobject]@{
      id = 'project-2'
      name = 'Life Log'
      identifier = 'LIFELOG'
      slug = 'daily-log'
    }

    Test-PlaneProjectMatchesMapping -Project $project -Mapping $mapping | Should -BeTrue
  }
}
