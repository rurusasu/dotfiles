#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixOSWSL.ps1
    . $PSScriptRoot/../../handlers/Handler.NixRebuild.ps1
    . $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1
}

Describe 'HermesAgentHandler' {
    BeforeEach {
        $script:handler = [HermesAgentHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:composeDir = Join-Path $TestDrive "docker\hermes-agent"
        $script:composeFile = Join-Path $script:composeDir "compose.yml"
        $script:userProfile = Join-Path $TestDrive "user"
        $script:oldUserProfile = $env:USERPROFILE
        $script:oldHome = $env:HOME
        $script:oldHermesDataDir = $env:HERMES_DATA_DIR
        $script:oldHermesBrowserDataDir = $env:HERMES_BROWSER_DATA_DIR
        $script:oldHermesBrowserViewPort = $env:HERMES_BROWSER_VIEW_PORT
        $script:dockerCalls = @()

        $script:ctx.Options["NixRebuildApplied"] = $true
        $script:ctx.Options["HermesAgent1PasswordEnabled"] = $false
        $script:ctx.Options["HermesAgentGitHub1PasswordEnabled"] = $false
        $script:ctx.Options["HermesAgentSlack1PasswordEnabled"] = $false
        Remove-Item -LiteralPath $script:userProfile -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:composeDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:userProfile -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value "services: {}" -Encoding UTF8

        $env:USERPROFILE = $script:userProfile
        Remove-Item Env:\HOME -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BROWSER_VIEW_PORT -ErrorAction SilentlyContinue

        Mock Write-Host { }
        Mock Get-Command {
            return [PSCustomObject]@{ Name = "docker"; Source = "C:\Program Files\Docker\Docker\resources\bin\docker.exe" }
        } -ParameterFilter { $Name -eq "docker" }
        Mock Test-DockerDaemon { return $true }
        Mock Test-WslAvailable { return $true }
        Mock Invoke-Wsl {
            $global:LASTEXITCODE = 0
            return @()
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:oldUserProfile
        if ($null -eq $script:oldHome) {
            Remove-Item Env:\HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:HOME = $script:oldHome
        }

        if ($null -eq $script:oldHermesDataDir) {
            Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:HERMES_DATA_DIR = $script:oldHermesDataDir
        }

        if ($null -eq $script:oldHermesBrowserDataDir) {
            Remove-Item Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:HERMES_BROWSER_DATA_DIR = $script:oldHermesBrowserDataDir
        }

        if ($null -eq $script:oldHermesBrowserViewPort) {
            Remove-Item Env:\HERMES_BROWSER_VIEW_PORT -ErrorAction SilentlyContinue
        }
        else {
            $env:HERMES_BROWSER_VIEW_PORT = $script:oldHermesBrowserViewPort
        }
    }

    Context 'Constructor' {
        It 'should set installer metadata' {
            $handler.Name | Should -Be "HermesAgent"
            $handler.Description | Should -Not -BeNullOrEmpty
            $handler.Order | Should -Be 56
            $handler.RequiresAdmin | Should -Be $false
            $handler.Phase | Should -Be 2
        }

        It 'should run after NixOS setup handlers' {
            $handler.Order | Should -BeGreaterThan ([NixOSWSLHandler]::new().Order)
            $handler.Order | Should -BeGreaterThan ([NixRebuildHandler]::new().Order)
        }
    }

    Context 'Compose file' {
        It 'should build a Hermes image with GitHub CLI and npx installed' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $dockerfilePath = Join-Path $repoRoot "docker\hermes-agent\Dockerfile"
            $ghWrapperPath = Join-Path $repoRoot "docker\hermes-agent\gh-wrapper.sh"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s*build:"
            $composeContent | Should -Match "(?m)^\s*context:\s*\."
            $composeContent | Should -Match "(?m)^\s*dockerfile:\s*Dockerfile"
            $dockerfilePath | Should -Exist
            $ghWrapperPath | Should -Exist

            $dockerfileContent = Get-Content -LiteralPath $dockerfilePath -Raw
            $dockerfileContent | Should -Match "nousresearch/hermes-agent:latest"
            $dockerfileContent | Should -Match "apt-get"
            $dockerfileContent | Should -Match "(?m)\bgh\b"
            $dockerfileContent | Should -Match "/usr/bin/gh --version"
            $dockerfileContent | Should -Match "COPY gh-wrapper\.sh /usr/local/bin/gh"
            $dockerfileContent | Should -Match "(?m)\bnpm\b"
            $dockerfileContent | Should -Match "npx --version"
            $dockerfileContent | Should -Match "xapi-mcp\.sh"
            $dockerfileContent | Should -Match "/usr/local/bin/hermes-xapi-mcp"
            $dockerfileContent | Should -Match "channel_directory\.py"
            $dockerfileContent | Should -Match 'types="public_channel,private_channel"'
            $dockerfileContent | Should -Match 'types="public_channel"'
            $dockerfileContent | Should -Match "ARTICLE_COLLECTOR_VERSION"
            $dockerfileContent | Should -Match "article-collector-linux-amd64"
            $dockerfileContent | Should -Match "article-collector-linux-arm64"
            $dockerfileContent | Should -Match "/usr/local/bin/article-collector"
            $dockerfileContent | Should -Match "article-collector --help"

            $ghWrapperContent = Get-Content -LiteralPath $ghWrapperPath -Raw
            $ghWrapperContent | Should -Match "GITHUB_PERSONAL_ACCESS_TOKEN"
            $ghWrapperContent | Should -Match "export GH_TOKEN="
            $ghWrapperContent | Should -Match "exec /usr/bin/gh"
        }

        It 'should include an X API MCP wrapper that ignores unresolved credential placeholders' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $wrapperPath = Join-Path $repoRoot "docker\hermes-agent\xapi-mcp.sh"
            $wrapperPath | Should -Exist

            $wrapperContent = Get-Content -LiteralPath $wrapperPath -Raw
            $wrapperContent | Should -Match "X_API_CLIENT_ID"
            $wrapperContent | Should -Match "CLIENT_ID"
            $wrapperContent | Should -Match ([regex]::Escape('${X_API_CLIENT_ID}'))
            $wrapperContent | Should -Match ([regex]::Escape('exec npx -y @xdevplatform/xurl mcp https://api.x.com/mcp'))
        }

        It 'should not inject the Hermes env file into every supervised gateway process' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Not -Match "(?m)^\s*env_file:"
            $composeContent | Should -Not -Match ([regex]::Escape('path: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.env'))
        }

        It 'should persist xurl OAuth cache for the X API MCP bridge' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match ([regex]::Escape('source: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.xurl'))
            $composeContent | Should -Match "(?m)^\s*target:\s*/root/\.xurl\s*$"
        }

        It 'should keep managed profile gateways under the root Hermes container supervisor' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s{2}hermes:"
            $composeContent | Should -Match "container_name:\s*hermes"
            $composeContent | Should -Match ([regex]::Escape('source: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}'))
            $composeContent | Should -Match "(?m)^\s*target:\s*/opt/data\s*$"
            foreach ($profile in @("rick", "hoffman", "risarisa")) {
                $composeContent | Should -Not -Match "(?m)^\s{2}${profile}:"
                $composeContent | Should -Not -Match "hermes-$profile"
                $composeContent | Should -Not -Match ([regex]::Escape("source: `${HERMES_DATA_DIR:-`${USERPROFILE:-`${HOME}}/.hermes}/profiles/$profile"))
                $composeContent | Should -Not -Match ([regex]::Escape("path: `${HERMES_DATA_DIR:-`${USERPROFILE:-`${HOME}}/.hermes}/profiles/$profile/.env"))
            }
        }

        It 'should expose the shared lifelog core through the root Hermes home' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s*LIFELOG_ROOT:\s*/opt/data/core/lifelog\s*$"
            $composeContent | Should -Not -Match ([regex]::Escape('source: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/core'))
        }

        It 'should rebuild the local Hermes image instead of pulling it from a registry' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $taskfilePath = Join-Path $repoRoot "Taskfile.yml"
            $taskfileContent = Get-Content -LiteralPath $taskfilePath -Raw

            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} build --pull hermes"
            $taskfileContent | Should -Not -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} pull"
        }

        It 'should define a dedicated non-host Google Chrome image contract for Hermes browser MCP' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $dockerfilePath = Join-Path $repoRoot "docker\hermes-browser\Dockerfile"
            $entrypointPath = Join-Path $repoRoot "docker\hermes-browser\entrypoint.sh"
            $clipboardPastePath = Join-Path $repoRoot "docker\hermes-browser\clipboard-paste.js"

            $dockerfilePath | Should -Exist
            $entrypointPath | Should -Exist
            $clipboardPastePath | Should -Exist

            $dockerfileContent = Get-Content -LiteralPath $dockerfilePath -Raw
            $dockerfileContent | Should -Match "FROM debian:bookworm-slim"
            $dockerfileContent | Should -Match "apt-get"
            $dockerfileContent | Should -Match "--no-install-recommends"
            $dockerfileContent | Should -Match ([regex]::Escape('rm -rf /var/lib/apt/lists/*'))
            $dockerfileContent | Should -Match ([regex]::Escape('https://dl.google.com/linux/linux_signing_key.pub'))
            $dockerfileContent | Should -Match ([regex]::Escape('signed-by=/etc/apt/keyrings/google-chrome.asc'))
            $dockerfileContent | Should -Match "(?m)\bgoogle-chrome-stable\b"
            $dockerfileContent | Should -Match ([regex]::Escape('dpkg --print-architecture'))
            $dockerfileContent | Should -Not -Match '(?m)apt-get install[^\r\n]*\bchromium(?:-sandbox)?\b'
            $dockerfileContent | Should -Match "(?m)\bfonts-noto-cjk\b"
            $dockerfileContent | Should -Match "(?m)\blocales\b"
            $dockerfileContent | Should -Match ([regex]::Escape('ja_JP.UTF-8 UTF-8'))
            $dockerfileContent | Should -Match "(?m)\blocale-gen\b"
            $dockerfileContent | Should -Match "(?m)^ENV LANG=ja_JP\.UTF-8"
            $dockerfileContent | Should -Match "LANGUAGE=ja_JP:ja"
            $dockerfileContent | Should -Match "LC_ALL=ja_JP\.UTF-8"
            $dockerfileContent | Should -Match "(?m)\bsocat\b"
            $dockerfileContent | Should -Match "(?m)\bpython3-minimal\b"
            $dockerfileContent | Should -Match "(?m)\bcurl\b"
            $dockerfileContent | Should -Match "(?m)\bxvfb\b"
            $dockerfileContent | Should -Match "(?m)\bx11vnc\b"
            $dockerfileContent | Should -Match "(?m)\bnovnc\b"
            $dockerfileContent | Should -Match "(?m)\bwebsockify\b"
            $dockerfileContent | Should -Match ([regex]::Escape('groupadd --system --gid 997 hermes-browser'))
            $dockerfileContent | Should -Match "useradd"
            $dockerfileContent | Should -Match '(?m)useradd[^\r\n]*--uid 997'
            $dockerfileContent | Should -Match '(?m)useradd[^\r\n]*--gid hermes-browser'
            $dockerfileContent | Should -Match "hermes-browser"
            $dockerfileContent | Should -Match "COPY entrypoint\.sh"
            $dockerfileContent | Should -Match "COPY clipboard-paste\.js /usr/share/novnc/app/clipboard-paste\.js"
            $dockerfileContent | Should -Match ([regex]::Escape('<script type="module" src="app/clipboard-paste.js"></script>'))
            $dockerfileContent | Should -Match ([regex]::Escape('ln -sf vnc.html /usr/share/novnc/index.html'))
            $dockerfileContent | Should -Match "COPY healthcheck\.sh"
            $dockerfileContent | Should -Match "chmod \+x"
            $dockerfileContent | Should -Match "(?m)^USER hermes-browser\s*$"
            $dockerfileContent | Should -Not -Match "chrome\.exe|chromium\.exe"

            $entrypointContent = Get-Content -LiteralPath $entrypointPath -Raw
            $entrypointContent | Should -Match "socat"
            $entrypointContent | Should -Match "TCP-LISTEN:9222,fork,reuseaddr,bind=0\.0\.0\.0"
            $entrypointContent | Should -Match 'UPSTREAM_HOST = "127\.0\.0\.1"'
            $entrypointContent | Should -Match "UPSTREAM_PORT = 9223"
            $entrypointContent | Should -Match "EXTERNAL_PORT = 9222"
            $entrypointContent | Should -Match "Host"
            $entrypointContent | Should -Match ([regex]::Escape('upstream_host = f"{UPSTREAM_HOST}:{UPSTREAM_PORT}"'))
            $entrypointContent | Should -Match ([regex]::Escape('external_host = get_header(request_headers, "Host")'))
            $entrypointContent | Should -Match ([regex]::Escape('external_host.encode("ascii")'))
            $entrypointContent | Should -Match "Content-Length"
            $entrypointContent | Should -Match ([regex]::Escape('/usr/bin/google-chrome-stable'))
            $entrypointContent | Should -Not -Match ([regex]::Escape('/usr/bin/chromium'))
            $entrypointContent | Should -Match 'DISPLAY="\$\{DISPLAY:-:99\}"'
            $entrypointContent | Should -Match ([regex]::Escape('display_number="${DISPLAY#*:}"'))
            $entrypointContent | Should -Match ([regex]::Escape('display_number="${display_number%%.*}"'))
            $entrypointContent | Should -Match ([regex]::Escape('rm -f "/tmp/.X${display_number}-lock" "/tmp/.X11-unix/X${display_number}"'))
            $entrypointContent | Should -Match "HERMES_BROWSER_XVFB_SCREEN:-1280x900x24"
            $entrypointContent | Should -Match "/usr/bin/Xvfb"
            $entrypointContent | Should -Match ([regex]::Escape('until xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do'))
            $entrypointContent | Should -Match "x11vnc"
            $entrypointContent | Should -Match "-listen 127\.0\.0\.1"
            $entrypointContent | Should -Match "-rfbport 5900"
            $entrypointContent | Should -Match "websockify"
            $entrypointContent | Should -Match "--web=/usr/share/novnc"
            $entrypointContent | Should -Match "0\.0\.0\.0:6080"
            $entrypointContent | Should -Match "127\.0\.0\.1:5900"
            $entrypointContent | Should -Not -Match "--headless=new"
            $entrypointContent | Should -Match "--remote-debugging-address=127\.0\.0\.1"
            $entrypointContent | Should -Match "--remote-debugging-port=9223"
            $entrypointContent | Should -Not -Match "--remote-debugging-address=0\.0\.0\.0"
            $entrypointContent | Should -Not -Match "--remote-debugging-port=9222"
            $entrypointContent | Should -Match "--user-data-dir=/data"
            $entrypointContent | Should -Match "--lang=ja"
            $entrypointContent | Should -Match "mkdir -p /data"
            $entrypointContent | Should -Match "SingletonLock"
            $entrypointContent | Should -Match "SingletonSocket"
            $entrypointContent | Should -Match "SingletonCookie"
            $entrypointContent | Should -Match ([regex]::Escape('rm -f /data/SingletonLock /data/SingletonSocket /data/SingletonCookie'))
            $entrypointContent | Should -Match '(?s)touch /data/\.hermes-browser-write-test.*rm -f /data/SingletonLock /data/SingletonSocket /data/SingletonCookie.*Xvfb.*x11vnc.*websockify.*socat.*chromium_pid=.*wait "\$chromium_pid"'
            $entrypointContent | Should -Match "monitor_helpers\(\)"
            $entrypointContent | Should -Match "xvfb_pid.*vnc_pid.*novnc_pid.*cdp_pid"
            $entrypointContent | Should -Match ([regex]::Escape('/proc/$pid/stat'))
            $entrypointContent | Should -Match "process_is_running\(\)"
            $entrypointContent | Should -Match "shutdown_requested=0"
            $entrypointContent | Should -Match "request_shutdown\(\)"
            $entrypointContent | Should -Match "trap request_shutdown TERM INT"
            $entrypointContent | Should -Match ([regex]::Escape('kill "$chromium_pid"'))
            $entrypointContent | Should -Match ([regex]::Escape('monitor_pid=$!'))
            $entrypointContent | Should -Not -Match "(?i)(?:`$HOME|`$USERPROFILE|/root|/home)/.*Singleton(?:Lock|Socket|Cookie)"
            $entrypointContent | Should -Not -Match "--no-sandbox"
            $entrypointContent | Should -Not -Match "chrome\.exe|chromium\.exe"

            $clipboardPasteContent = Get-Content -LiteralPath $clipboardPastePath -Raw
            $clipboardPasteContent | Should -Match 'document\.addEventListener\(\s*"keydown"'
            $clipboardPasteContent | Should -Match 'document\.addEventListener\(\s*"paste"'
            $clipboardPasteContent | Should -Match ([regex]::Escape('clipboardData?.getData("text/plain")'))
            $clipboardPasteContent | Should -Match ([regex]::Escape('new TextEncoder().encode(text)'))
            $clipboardPasteContent | Should -Match ([regex]::Escape('RFB.messages.clientCutText'))
            $clipboardPasteContent | Should -Match "XK_Control_L"
            $clipboardPasteContent | Should -Match "XK_v"
            $clipboardPasteContent | Should -Match ([regex]::Escape('#noVNC_clipboard'))

            $imageEntrypointContent = "$dockerfileContent`n$entrypointContent"
            $imageEntrypointContent | Should -Match ([regex]::Escape('/usr/bin/google-chrome-stable'))
            $imageEntrypointContent | Should -Match '(?m)(?<![A-Za-z0-9_-])/data(?![A-Za-z0-9_-])'
            $imageEntrypointContent | Should -Not -Match "--no-sandbox"

            @(
                '(?i)(?<![A-Za-z0-9])brave(?:browser)?(?:\.exe)?(?![A-Za-z0-9])',
                '(?i)(?<![A-Za-z0-9])node(?:js)?(?:\.exe)?(?![A-Za-z0-9])',
                '(?i)(?<![A-Za-z0-9])npm(?:\.cmd|\.exe)?(?![A-Za-z0-9])',
                '(?i)(?<![A-Za-z0-9])python(?:\d+(?:\.\d+)*)?\.exe(?![A-Za-z0-9])'
            ) | ForEach-Object {
                $imageEntrypointContent | Should -Not -Match $_
            }

            $forbiddenCdpEndpointPattern = '(?i)(?:127\.0\.0\.1|localhost):9222|host\.docker\.internal(?::\d+)?'

            @(
                $forbiddenCdpEndpointPattern
            ) | ForEach-Object {
                $imageEntrypointContent | Should -Not -Match $_
            }

            $entrypointContent | Should -Not -Match '(?i)\b(?:ws|wss|http|https)://[^\s''"`]+'

            'host.docker.internal' | Should -Match $forbiddenCdpEndpointPattern
            'host.docker.internal:9222' | Should -Match $forbiddenCdpEndpointPattern
            'host.docker.internal:9999' | Should -Match $forbiddenCdpEndpointPattern

            @(
                '(?i)(?:[A-Za-z]:[\\/]|\\\\|/mnt/[a-z]/|%USERPROFILE%|%LOCALAPPDATA%|\$\{USERPROFILE\}|\$\{HOME\}|\$HOME\b|/Users/|Program Files|AppData|\.exe\b|\.bat\b|\.cmd\b|\.ps1\b)'
            ) | ForEach-Object {
                $entrypointContent | Should -Not -Match $_
            }
        }

        It 'should define a streamable Browser MCP image contract backed by the Compose browser service' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $dockerfilePath = Join-Path $repoRoot "docker\hermes-browser-mcp\Dockerfile"
            $packageJsonPath = Join-Path $repoRoot "docker\hermes-browser-mcp\package.json"
            $packageLockPath = Join-Path $repoRoot "docker\hermes-browser-mcp\package-lock.json"

            $dockerfilePath | Should -Exist
            $packageJsonPath | Should -Exist
            $packageLockPath | Should -Exist

            $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
            $packageJson.dependencies.'chrome-devtools-mcp' | Should -Be '1.4.0'
            $packageJson.dependencies.'mcp-proxy' | Should -Be '6.5.2'

            $packageLock = Get-Content -LiteralPath $packageLockPath -Raw | ConvertFrom-Json -AsHashtable
            $packageLock.packages.Keys | Should -Contain ''
            $packageLock.packages[''].dependencies['chrome-devtools-mcp'] | Should -Be '1.4.0'
            $packageLock.packages[''].dependencies['mcp-proxy'] | Should -Be '6.5.2'

            $dockerfileContent = Get-Content -LiteralPath $dockerfilePath -Raw
            $dockerfileContent | Should -Match '(?m)^FROM node:22-bookworm-slim\s*$'
            $dockerfileContent | Should -Match 'COPY package\.json package-lock\.json'
            $dockerfileContent | Should -Match 'npm ci --omit=dev'
            $dockerfileContent | Should -Match 'CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1'
            $dockerfileContent | Should -Match 'NO_UPDATE_CHECKS=1'
            $dockerfileContent | Should -Match 'USER node'
            $dockerfileContent | Should -Match '(?m)^HEALTHCHECK\b'
            $dockerfileContent | Should -Match 'node:net'
            $dockerfileContent | Should -Match 'connect\(\{host:\s*["'']127\.0\.0\.1["''],\s*port:\s*8080\}\)'
            $dockerfileContent | Should -Match '"--server", "stream"'
            $dockerfileContent | Should -Match '"--port", "8080"'
            $dockerfileContent | Should -Match '--browser-url=http://chromium:9222'
            $dockerfileContent | Should -Match '--no-usage-statistics'
            $dockerfileContent | Should -Match 'node_modules/.bin/mcp-proxy'
            $dockerfileContent | Should -Match 'node_modules/.bin/chrome-devtools-mcp'
            $dockerfileContent | Should -Not -Match '/ping|fetch\('
            $dockerfileContent | Should -Not -Match 'localhost:9222|127\.0\.0\.1:9222|host\.docker\.internal'
            $dockerfileContent | Should -Not -Match 'chrome\.exe|chromium\.exe|python(?:\d+(?:\.\d+)*)?(?:\.exe)?'
        }

        It 'should wire Google Chrome and Browser MCP into the Hermes Compose network while publishing only noVNC locally' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw
            $chromiumService = [regex]::Match($composeContent, "(?ms)^\s{2}chromium:.*?(?=^\s{2}\S|\z)").Value

            $composeContent | Should -Match "(?m)^\s{2}hermes:"
            $composeContent | Should -Match "(?m)^\s{2}chromium:"
            $composeContent | Should -Match "(?m)^\s{2}browser-mcp:"
            $composeContent | Should -Match "(?ms)^\s{2}hermes:.*?depends_on:\s*`r?`n\s{6}browser-mcp:\s*`r?`n\s{8}condition:\s*service_healthy"
            $composeContent | Should -Match "(?ms)^\s{2}browser-mcp:.*?depends_on:\s*`r?`n\s{6}chromium:\s*`r?`n\s{8}condition:\s*service_healthy"

            foreach ($service in @("hermes", "chromium", "browser-mcp")) {
                $composeContent | Should -Match "(?ms)^\s{2}${service}:.*?networks:\s*`r?`n\s{6}- hermes-browser"
            }

            $composeContent | Should -Match "(?ms)^\s{2}chromium:.*?build:\s*`r?`n\s{6}context:\s*\.\./hermes-browser"
            $composeContent | Should -Match "(?ms)^\s{2}chromium:.*?shm_size:\s*2g"
            $chromiumService | Should -Not -Match "(?m)^\s{4}cap_add:\s*$"
            $chromiumService | Should -Not -Match "(?m)^\s*-\s*SYS_ADMIN\s*$"
            $composeContent | Should -Match "(?ms)^\s{2}chromium:.*?source:\s*\$\{HERMES_BROWSER_DATA_DIR:-\$\{USERPROFILE:-\$\{HOME\}\}/\.hermes/\.browser\}\s*`r?`n\s{8}target:\s*/data"
            $composeContent | Should -Match "(?ms)^\s{2}chromium:.*?healthcheck:.*?/usr/local/bin/healthcheck\.sh"
            $composeContent | Should -Match '(?m)^\s*-\s*"127\.0\.0\.1:\$\{HERMES_BROWSER_VIEW_PORT:-6080\}:6080"\s*$'
            $composeContent | Should -Not -Match "(?m)^\s*-\s*[""']?(?:127\.0\.0\.1:|0\.0\.0\.0:|\$\{[^}]+}:)?5900:5900[""']?\s*$"

            $composeContent | Should -Match "(?ms)^\s{2}browser-mcp:.*?build:\s*`r?`n\s{6}context:\s*\.\./hermes-browser-mcp"
            $composeContent | Should -Match "(?ms)^\s{2}browser-mcp:.*?healthcheck:.*?8080"

            $composeContent | Should -Match "(?m)^networks:\s*$"
            $composeContent | Should -Match "(?ms)^networks:\s*`r?`n\s{2}hermes-browser:\s*`r?`n\s{4}name:\s*hermes-browser\s*`r?`n\s{4}driver:\s*bridge"
            $composeContent | Should -Not -Match "(?ms)^networks:.*?internal:\s*true"
            $composeContent | Should -Not -Match "(?m)^\s*privileged:\s*true\s*$"
            $composeContent | Should -Not -Match "(?m)^\s*-\s*[""']?(?:127\.0\.0\.1:|0\.0\.0\.0:|\$\{[^}]+}:)?9222:9222[""']?\s*$"
            $composeContent | Should -Not -Match "(?m)^\s*-\s*[""']?(?:127\.0\.0\.1:|0\.0\.0\.0:|\$\{[^}]+}:)?8080:8080[""']?\s*$"

            $healthcheckPath = Join-Path $repoRoot "docker\hermes-browser\healthcheck.sh"
            $healthcheckPath | Should -Exist
            $healthcheckContent = Get-Content -LiteralPath $healthcheckPath -Raw
            $healthcheckContent | Should -Match "/json/version"
            $healthcheckContent | Should -Match "127\.0\.0\.1:6080/"
            $healthcheckContent | Should -Match "127\.0\.0\.1.*5900"
        }

        It 'should expose Hermes browser lifecycle tasks' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $taskfilePath = Join-Path $repoRoot "Taskfile.yml"
            $taskfileContent = Get-Content -LiteralPath $taskfilePath -Raw

            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} build --pull hermes chromium browser-mcp"
            foreach ($task in @("pull", "restart", "logs", "ps")) {
                $taskfileContent | Should -Match "(?m)^\s{2}hermes:browser:${task}:"
            }

            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} build --pull chromium browser-mcp"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} up -d --force-recreate chromium browser-mcp"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} logs -f --tail=100 chromium browser-mcp"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} ps chromium browser-mcp"
        }

        It 'should expose managed profile gateway lifecycle tasks' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $taskfilePath = Join-Path $repoRoot "Taskfile.yml"
            $taskfileContent = Get-Content -LiteralPath $taskfilePath -Raw

            $taskfileContent | Should -Match "(?m)^\s{2}hermes:profile:init:"
            $taskfileContent | Should -Match "PROFILE: '{{.CLI_ARGS | default `"risarisa`"}}'"
            $taskfileContent | Should -Match "docker exec hermes sh -lc"
            $taskfileContent | Should -Match "git init -b main"

            foreach ($profile in @("rick", "hoffman", "risarisa")) {
                $taskfileContent | Should -Match "(?m)^\s{2}hermes:$profile:up:"
                $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} up -d hermes"
                $taskfileContent | Should -Match "/opt/hermes/.venv/bin/hermes -p $profile gateway start"
                $taskfileContent | Should -Match "(?m)^\s{2}hermes:$profile:down:"
                $taskfileContent | Should -Match "/opt/hermes/.venv/bin/hermes -p $profile gateway stop"
                $taskfileContent | Should -Match "(?m)^\s{2}hermes:$profile:restart:"
                $taskfileContent | Should -Match "/opt/hermes/.venv/bin/hermes -p $profile gateway restart"
                $taskfileContent | Should -Match "(?m)^\s{2}hermes:$profile:logs:"
                $taskfileContent | Should -Match "/opt/data/logs/gateways/$profile/current"
            }
            $taskfileContent | Should -Not -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} (up|stop|logs).*(rick|hoffman|risarisa)"
        }
    }

    Context 'CanApply' {
        It 'should return false when Hermes setup is skipped by option' {
            $ctx.Options["SkipHermesAgent"] = $true

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when compose file is missing' {
            Remove-Item -LiteralPath $script:composeFile -Force

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when docker command is unavailable' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "docker" }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when Docker daemon is not ready' {
            Mock Test-DockerDaemon { return $false }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when WSL is unavailable' {
            Mock Test-WslAvailable { return $false }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when the NixOS distro is not runnable' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return @("not found")
            }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when NixRebuild has not completed in the current setup run' {
            $ctx.Options.Remove("NixRebuildApplied")

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return true when compose file, Docker daemon, NixOS distro, and NixRebuild are available' {
            $handler.CanApply($ctx) | Should -Be $true

            Should -Invoke Test-DockerDaemon -Times 1 -ParameterFilter {
                $TimeoutSeconds -eq 15
            }
            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
                $TimeoutSeconds -eq (Get-WslCheckTimeoutSecond) -and
                $Arguments[0] -eq "-d" -and
                $Arguments[1] -eq $ctx.DistroName -and
                $Arguments[2] -eq "-u" -and
                $Arguments[3] -eq "root" -and
                $Arguments[4] -eq "--" -and
                $Arguments[5] -eq "true"
            }
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)

                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @("generated-password", 'scrypt$hash')
                }

                if ($Arguments[0] -eq "compose") {
                    $global:LASTEXITCODE = 0
                    return @("started")
                }

                if ($Arguments[0] -eq "exec") {
                    $global:LASTEXITCODE = 0
                    return @("lifelog synced")
                }

                $global:LASTEXITCODE = 1
                return @("unexpected docker call")
            }
        }

        It 'should generate dashboard auth and start the compose service' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "http://127\.0\.0\.1:9119"
            $result.Message | Should -Match "http://127\.0\.0\.1:6080"
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $passwordPath = Join-Path $script:userProfile ".hermes\dashboard-basic-auth-password.txt"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $passwordContent = Get-Content -LiteralPath $passwordPath -Raw

            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_SECRET="
            $passwordContent | Should -Match "generated-password"

            $composeCall = @($script:dockerCalls | Where-Object { $_[0] -eq "compose" })[0]
            $composeCall | Should -Contain "-f"
            $composeCall | Should -Contain $script:composeFile
            $composeCall | Should -Not -Contain "--profile"
            $composeCall | Should -Not -Contain "rick"
            $composeCall | Should -Not -Contain "hoffman"
            $composeCall | Should -Not -Contain "risarisa"
            $composeCall | Should -Contain "up"
            $composeCall | Should -Contain "-d"
            $composeCall | Should -Contain "--build"
            $composeCall | Should -Contain "--force-recreate"
            $composeCall | Should -Contain "--remove-orphans"
        }

        It 'should create the default browser profile directory before starting compose' {
            $browserProfileDir = Join-Path $script:userProfile ".hermes\.browser"

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $browserProfileDir | Should -Exist
        }

        It 'should show the configured browser viewer port in the setup result' {
            $oldPort = $env:HERMES_BROWSER_VIEW_PORT
            try {
                $env:HERMES_BROWSER_VIEW_PORT = "16080"
                $result = $handler.Apply($ctx)
                $result.Success | Should -Be $true
                $result.Message | Should -Match "http://127\.0\.0\.1:16080"
            }
            finally {
                if ($null -eq $oldPort) {
                    Remove-Item Env:\HERMES_BROWSER_VIEW_PORT -ErrorAction SilentlyContinue
                }
                else {
                    $env:HERMES_BROWSER_VIEW_PORT = $oldPort
                }
            }
        }

        It 'should write the configured browser viewer port into the Slack registration guide' {
            $env:HERMES_BROWSER_VIEW_PORT = "16080"

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $slackRegistrationDoc = Get-Content -LiteralPath (Join-Path $script:userProfile ".hermes\docs\slack-app-registration.md") -Raw
            $slackRegistrationDoc | Should -Match "http://127\.0\.0\.1:16080"
            $slackRegistrationDoc | Should -Not -Match "HERMES_BROWSER_VIEW_PORT"
        }

        It 'should create the browser profile directory from HERMES_BROWSER_DATA_DIR when set' {
            $customBrowserProfileDir = Join-Path $TestDrive "custom-browser-profile"
            $env:HERMES_BROWSER_DATA_DIR = $customBrowserProfileDir

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $customBrowserProfileDir | Should -Exist
            (Join-Path $script:userProfile ".hermes\.browser") | Should -Not -Exist
        }

        It 'should configure the default Codex model in config.yaml' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configPath = Join-Path $script:userProfile ".hermes\config.yaml"
            $configContent = Get-Content -LiteralPath $configPath -Raw

            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
        }

        It 'should replace stale Hermes model config while preserving other settings' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  default: anthropic/claude-opus-4.6",
                "  provider: auto",
                "  base_url: https://openrouter.ai/api/v1",
                "terminal:",
                "  backend: local"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "claude-opus-4\.6|openrouter|model\.default|model\.provider"
            $configContent | Should -Match "(?m)^terminal:\r?\n  backend: local"
        }

        It 'should preserve nested model settings while replacing only the top-level model config' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "auxiliary:",
                "  vision:",
                "    model: local-vision-model",
                "    provider: local-provider",
                "model:",
                "  default: stale-main-model",
                "  provider: auto",
                "agent:",
                "  max_turns: 60"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^auxiliary:\r?\n  vision:\r?\n    model: local-vision-model\r?\n    provider: local-provider"
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "stale-main-model"
        }

        It 'should normalize scalar and literal model keys from manual config edits' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model: gpt-5.5",
                "model.default: gpt-5.5",
                "model.provider: openai-codex",
                "agent:",
                "  max_turns: 60"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "(?m)^model\.(default|provider):"
            $configContent | Should -Match "(?m)^agent:\r?\n  max_turns: 60"
        }

        It 'should preserve custom terminal env passthrough entries while replacing GitHub token aliases' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $rickDir = Join-Path $dataDir "profiles\rick"
            $hoffmanDir = Join-Path $dataDir "profiles\hoffman"
            New-Item -ItemType Directory -Path $rickDir, $hoffmanDir -Force | Out-Null
            $rootConfigPath = Join-Path $dataDir "config.yaml"
            $rickConfigPath = Join-Path $rickDir "config.yaml"
            $hoffmanConfigPath = Join-Path $hoffmanDir "config.yaml"
            Set-Content -LiteralPath $rootConfigPath -Encoding UTF8 -Value @(
                "terminal:",
                "  backend: local",
                "  env_passthrough:",
                "    - NPM_TOKEN",
                "    - GH_TOKEN",
                "    - GITHUB_TOKEN"
            )
            Set-Content -LiteralPath $rickConfigPath -Encoding UTF8 -Value @(
                "terminal:",
                "  timeout: 180"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            foreach ($configPath in @($rootConfigPath, $rickConfigPath, $hoffmanConfigPath)) {
                $configContent = Get-Content -LiteralPath $configPath -Raw
                $configContent | Should -Match "(?m)^terminal:"
                $configContent | Should -Match "(?m)^  env_passthrough:\r?$"
                $configContent | Should -Match "(?m)^    - GITHUB_PERSONAL_ACCESS_TOKEN\r?$"
                $configContent | Should -Not -Match "(?m)^\s+- GH_TOKEN\r?$"
                $configContent | Should -Not -Match "(?m)^\s+- GITHUB_TOKEN\r?$"
            }
            (Get-Content -LiteralPath $rootConfigPath -Raw) | Should -Match "(?m)^  backend: local\r?$"
            (Get-Content -LiteralPath $rootConfigPath -Raw) | Should -Match "(?m)^    - NPM_TOKEN\r?$"
            (Get-Content -LiteralPath $rickConfigPath -Raw) | Should -Match "(?m)^  timeout: 180\r?$"
        }

        It 'should require initial Slack mentions while allowing thread follow-ups without repeated mentions' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $rickDir = Join-Path $dataDir "profiles\rick"
            $hoffmanDir = Join-Path $dataDir "profiles\hoffman"
            New-Item -ItemType Directory -Path $rickDir, $hoffmanDir -Force | Out-Null
            $rootConfigPath = Join-Path $dataDir "config.yaml"
            $rickConfigPath = Join-Path $rickDir "config.yaml"
            $hoffmanConfigPath = Join-Path $hoffmanDir "config.yaml"
            Set-Content -LiteralPath $rootConfigPath -Encoding UTF8 -Value @(
                "agent:",
                "  max_turns: 60"
            )
            Set-Content -LiteralPath $rickConfigPath -Encoding UTF8 -Value @(
                "slack:",
                "  require_mention: true",
                "  allow_bots: none",
                "  allowed_channels: C04AHA0CE4W",
                "display:",
                "  tool_progress: none"
            )
            Set-Content -LiteralPath $hoffmanConfigPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $rootConfig = Get-Content -LiteralPath $rootConfigPath -Raw
            $rootConfig | Should -Match "(?m)^slack:\r?\n  require_mention: true\r?\n  strict_mention: false\r?\n  allow_bots: mentions"
            $rootConfig | Should -Match "(?m)^agent:\r?\n  max_turns: 60"

            $rickConfig = Get-Content -LiteralPath $rickConfigPath -Raw
            $rickConfig | Should -Match "(?m)^slack:\r?\n  require_mention: true\r?\n  strict_mention: false\r?\n  allow_bots: mentions\r?\n  allowed_channels: C04AHA0CE4W"
            $rickConfig | Should -Not -Match "allow_bots: none"
            $rickConfig | Should -Match "(?m)^display:\r?\n  tool_progress: none"

            $hoffmanConfig = Get-Content -LiteralPath $hoffmanConfigPath -Raw
            $hoffmanConfig | Should -Match "(?m)^slack:\r?\n  require_mention: true\r?\n  strict_mention: false\r?\n  allow_bots: mentions"
        }

        It 'should fall back to generated dashboard auth when 1Password CLI is unavailable' {
            $ctx.Options.Remove("HermesAgent1PasswordEnabled")
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $passwordPath = Join-Path $script:userProfile ".hermes\dashboard-basic-auth-password.txt"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $passwordContent = Get-Content -LiteralPath $passwordPath -Raw

            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $passwordContent | Should -Match "generated-password"
        }

        It 'should fail before compose when 1Password is required but unavailable' {
            $ctx.Options.Remove("HermesAgent1PasswordEnabled")
            $ctx.Options["HermesAgentRequire1Password"] = $true
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1Password CLI"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should fail before compose when enabled root Slack tokens cannot be configured' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Slack"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should preserve existing dashboard auth without regenerating the password' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin",
                'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing$hash',
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=existing-secret"
            )
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)
                if ($Arguments[0] -eq "run") {
                    throw "password hash should not be regenerated"
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing$hash'))
            Test-Path -LiteralPath (Join-Path $dataDir "dashboard-basic-auth-password.txt") | Should -Be $false
        }

        It 'should sync dashboard auth into managed profile env files without replacing profile secrets' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $rickDir = Join-Path $dataDir "profiles\rick"
            $hoffmanDir = Join-Path $dataDir "profiles\hoffman"
            New-Item -ItemType Directory -Path $rickDir, $hoffmanDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rickDir ".env") -Encoding UTF8 -Value @(
                "SLACK_BOT_TOKEN=xoxb-rick-token",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=old",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=old-plaintext",
                'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=old$hash',
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=old-secret"
            )
            Set-Content -LiteralPath (Join-Path $hoffmanDir ".env") -Encoding UTF8 -Value @(
                "SLACK_APP_TOKEN=xapp-hoffman-token"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $rickEnvContent = Get-Content -LiteralPath (Join-Path $rickDir ".env") -Raw
            $rickEnvContent | Should -Match "SLACK_BOT_TOKEN=xoxb-rick-token"
            $rickEnvContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $rickEnvContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $rickEnvContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_SECRET="
            $rickEnvContent | Should -Not -Match "old-plaintext"
            $rickEnvContent | Should -Not -Match ([regex]::Escape('old$hash'))
            $rickEnvContent | Should -Not -Match "old-secret"

            $hoffmanEnvContent = Get-Content -LiteralPath (Join-Path $hoffmanDir ".env") -Raw
            $hoffmanEnvContent | Should -Match "SLACK_APP_TOKEN=xapp-hoffman-token"
            $hoffmanEnvContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $hoffmanEnvContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $hoffmanEnvContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_SECRET="
        }

        It 'should prefer 1Password dashboard auth and avoid writing a plaintext password file' {
            $ctx.Options["HermesAgent1PasswordEnabled"] = $true
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            $passwordPath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=local-admin",
                'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=local$hash',
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=local-secret"
            )
            Set-Content -LiteralPath $passwordPath -Encoding UTF8 -Value "stale-local-password"
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "username"
                        label   = "username"
                        purpose = "USERNAME"
                        value   = "admin"
                    },
                    @{
                        id      = "password"
                        label   = "password"
                        purpose = "PASSWORD"
                        value   = "shared-password"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $Arguments
                $null = $TimeoutSeconds
                return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
            }
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @('scrypt$onepassword')
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$onepassword'))
            $envContent | Should -Not -Match "local-admin"
            $envContent | Should -Not -Match "local-secret"
            Test-Path -LiteralPath $passwordPath | Should -Be $false
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "Hermes Agent Dashboard" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "Private"
            }
        }

        It 'should provision the Hermes lifelog GitHub token from a generic 1Password item' {
            $ctx.Options["HermesAgentGitHub1PasswordEnabled"] = $true
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "credential"
                        label   = "credential"
                        purpose = ""
                        value   = "github-token"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                if ($Arguments -contains "GitHubUsedUserPAT") {
                    return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath (Join-Path $script:userProfile ".hermes\.env") -Raw
            $envContent | Should -Match "GITHUB_PERSONAL_ACCESS_TOKEN=github-token"
            $envContent | Should -Match "GH_TOKEN=github-token"
            $envContent | Should -Match "GITHUB_TOKEN=github-token"
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments -contains "GitHubUsedUserPAT" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "Private"
            }
        }

        It 'should configure Slack environment from the Hermes 1Password item' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "bot_token"
                        label   = "bot_token"
                        purpose = ""
                        value   = "xoxb-test-bot-token"
                    },
                    @{
                        id      = "app_level_token"
                        label   = "app_level_token"
                        purpose = ""
                        value   = "xapp-test-app-token"
                    },
                    @{
                        id      = "SLACK_ALLOWED_USERS"
                        label   = "SLACK_ALLOWED_USERS"
                        purpose = ""
                        value   = "U04BDJU87KJ"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                if ($Arguments -contains "SlackBot-Hermes") {
                    return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "SLACK_BOT_TOKEN=xoxb-test-bot-token"
            $envContent | Should -Match "SLACK_APP_TOKEN=xapp-test-app-token"
            $envContent | Should -Match "SLACK_ALLOWED_USERS=U04BDJU87KJ"
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "SlackBot-Hermes" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "Private"
            }
        }

        It 'should configure managed profile Slack environment from its dedicated 1Password item' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $false
            $ctx.Options["HermesAgentRisarisaSlack1PasswordEnabled"] = $true
            $dataDir = Join-Path $script:userProfile ".hermes"
            $risarisaDir = Join-Path $dataDir "profiles\risarisa"
            $risarisaEnvPath = Join-Path $risarisaDir ".env"
            New-Item -ItemType Directory -Path $risarisaDir -Force | Out-Null
            Set-Content -LiteralPath $risarisaEnvPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "TELEGRAM_BOT_TOKEN=cloned-telegram-token",
                "SLACK_BOT_TOKEN=xoxb-cloned-default",
                "SLACK_APP_TOKEN=xapp-cloned-default",
                "SLACK_ALLOWED_USERS=UDEFAULT"
            )
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "bot_token"
                        label   = "bot_token"
                        purpose = ""
                        value   = "xoxb-risarisa-bot-token"
                    },
                    @{
                        id      = "app_level_token"
                        label   = "app_level_token"
                        purpose = ""
                        value   = "xapp-risarisa-app-token"
                    },
                    @{
                        id      = "SLACK_ALLOWED_USERS"
                        label   = "SLACK_ALLOWED_USERS"
                        purpose = ""
                        value   = "URISARISA"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                if ($Arguments -contains "SlackBot-Risarisa") {
                    return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $risarisaEnvPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match "SLACK_BOT_TOKEN=xoxb-risarisa-bot-token"
            $envContent | Should -Match "SLACK_APP_TOKEN=xapp-risarisa-app-token"
            $envContent | Should -Match "SLACK_ALLOWED_USERS=URISARISA"
            $envContent | Should -Not -Match "xoxb-cloned-default"
            $envContent | Should -Not -Match "TELEGRAM_BOT_TOKEN"
            $envContent | Should -Not -Match "cloned-telegram-token"
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "SlackBot-Risarisa" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "Private"
            }
        }

        It 'should configure Slack tokens for every managed profile dynamically' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $ctx.Options["HermesAgentManagedProfiles"] = "rick,hoffman,risarisa,newagent"
            $dataDir = Join-Path $script:userProfile ".hermes"
            $profilesDir = Join-Path $dataDir "profiles"
            $profileNames = @("rick", "hoffman", "risarisa", "newagent")
            foreach ($profileName in $profileNames) {
                $profileDir = Join-Path $profilesDir $profileName
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $profileDir ".env") -Encoding UTF8 -Value @(
                    "OTHER=$profileName"
                )
            }

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                $itemName = $Arguments[2]
                if ($itemName -notmatch '^SlackBot-') {
                    return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
                }

                $suffix = $itemName.Substring("SlackBot-".Length).ToLowerInvariant()
                return [PSCustomObject]@{
                    Output   = @(@{
                            fields = @(
                                @{
                                    id      = "bot_token"
                                    label   = "bot_token"
                                    purpose = ""
                                    value   = "xoxb-$suffix"
                                },
                                @{
                                    id      = "app_level_token"
                                    label   = "app_level_token"
                                    purpose = ""
                                    value   = "xapp-$suffix"
                                },
                                @{
                                    id      = "SLACK_ALLOWED_USERS"
                                    label   = "SLACK_ALLOWED_USERS"
                                    purpose = ""
                                    value   = "U-$suffix"
                                }
                            )
                        } | ConvertTo-Json -Compress)
                    ExitCode = 0
                }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            foreach ($profileName in $profileNames) {
                $profileEnvContent = Get-Content -LiteralPath (Join-Path $profilesDir "$profileName\.env") -Raw
                $profileEnvContent | Should -Match "OTHER=$profileName"
                $profileEnvContent | Should -Match "SLACK_BOT_TOKEN=xoxb-$profileName"
                $profileEnvContent | Should -Match "SLACK_APP_TOKEN=xapp-$profileName"
                $profileEnvContent | Should -Match "SLACK_ALLOWED_USERS=U-$profileName"
            }
        }

        It 'should fail before compose when any managed profile Slack token cannot be configured' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $ctx.Options["HermesAgentManagedProfiles"] = "rick,newagent"
            $dataDir = Join-Path $script:userProfile ".hermes"
            $profilesDir = Join-Path $dataDir "profiles"
            foreach ($profileName in @("rick", "newagent")) {
                $profileDir = Join-Path $profilesDir $profileName
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $profileDir ".env") -Encoding UTF8 -Value @(
                    "OTHER=$profileName"
                )
            }

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                $itemName = $Arguments[2]
                if ($itemName -eq "SlackBot-Newagent") {
                    return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
                }
                if ($itemName -match '^SlackBot-') {
                    return [PSCustomObject]@{
                        Output   = @(@{
                                fields = @(
                                    @{
                                        id      = "bot_token"
                                        label   = "bot_token"
                                        purpose = ""
                                        value   = "xoxb-ok"
                                    },
                                    @{
                                        id      = "app_level_token"
                                        label   = "app_level_token"
                                        purpose = ""
                                        value   = "xapp-ok"
                                    },
                                    @{
                                        id      = "SLACK_ALLOWED_USERS"
                                        label   = "SLACK_ALLOWED_USERS"
                                        purpose = ""
                                        value   = "UOK"
                                    }
                                )
                            } | ConvertTo-Json -Compress)
                        ExitCode = 0
                    }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Slack"
            $result.Message | Should -Match "newagent"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should bootstrap separate Git-managed profile home policy for a managed profile' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $profileDir = Join-Path $dataDir "profiles\risarisa"
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Encoding UTF8 -Value @(
                ".env",
                "memories/"
            )
            Set-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Encoding UTF8 -Value "Default profile soul."
            Set-Content -LiteralPath (Join-Path $profileDir "SOUL.md") -Encoding UTF8 -Value "Risarisa profile soul."

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $rootGitignore = Get-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Raw
            $rootGitignore | Should -Match "(?m)^profiles/\r?$"

            $sharedDocPath = Join-Path $dataDir "docs\profile-home-layout.md"
            $sharedDocPath | Should -Exist
            $sharedDoc = Get-Content -LiteralPath $sharedDocPath -Raw
            $sharedDoc | Should -Match "Hermes profile homes should keep the filesystem layout"
            $sharedDoc | Should -Match "hermes profile create <name>"
            $sharedDoc | Should -Match "Do not delete or flatten this physical layout"
            $sharedDoc | Should -Match "s6 supervises profile gateways"
            $sharedDoc | Should -Match "Do not run another Hermes gateway container"
            $sharedDoc | Should -Match "do not copy the shared root layout doc"
            $sharedDoc | Should -Match "memories/"
            $sharedDoc | Should -Match "auth\.json"
            $sharedDoc | Should -Match "Profile Gateway Runtime Secrets"
            $sharedDoc | Should -Match "model-provider auth"
            $sharedDoc | Should -Match "profile\.yaml"
            $sharedDoc | Should -Match "slack-manifest\.json"
            $sharedDoc | Should -Match "AGENTS.md"
            $sharedDoc | Should -Not -Match ([string][char]7)

            $slackRegistrationDocPath = Join-Path $dataDir "docs\slack-app-registration.md"
            $slackRegistrationDocPath | Should -Exist
            $slackRegistrationDoc = Get-Content -LiteralPath $slackRegistrationDocPath -Raw
            $slackRegistrationDoc | Should -Match "Hermes Slack App Registration"
            $slackRegistrationDoc | Should -Match "http://127\.0\.0\.1:6080"
            $slackRegistrationDoc | Should -Match "https://api\.slack\.com/apps\?new_app=1"
            $slackRegistrationDoc | Should -Match "slack-manifest\.json"
            $slackRegistrationDoc | Should -Match "connections:write"
            $slackRegistrationDoc | Should -Match "SLACK_BOT_TOKEN"
            $slackRegistrationDoc | Should -Match "SLACK_APP_TOKEN"
            $slackRegistrationDoc | Should -Match "SLACK_ALLOWED_USERS"
            $slackRegistrationDoc | Should -Match "SlackBot-<ProfileTitle>"
            $slackRegistrationDoc | Should -Match "Do not read generated Slack token values back through Browser MCP or tool output"
            $slackRegistrationDoc | Should -Match "Do not pass generated Slack token values through shell arguments"
            $slackRegistrationDoc | Should -Match "Pause before token reveal or extraction"
            $slackRegistrationDoc | Should -Match "approved non-logged secret channel"
            $slackRegistrationDoc | Should -Match ([regex]::Escape('leave the profile `.env` unchanged'))
            $slackRegistrationDoc | Should -Not -Match ([string][char]7)

            $rootSoul = Get-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Raw
            $rootSoul | Should -Match "/opt/data/docs/profile-home-layout.md"
            $rootSoul | Should -Match "auth\.json"
            $rootSoul | Should -Match "/opt/data/docs/slack-app-registration.md"
            $rootSoul | Should -Match "Slack App registration"
            $rootSoul | Should -Match ([regex]::Escape('Do not read generated Slack token values back through Browser MCP or tool output'))
            $rootSoul | Should -Not -Match ([string][char]7)

            $profileGitignorePath = Join-Path $profileDir ".gitignore"
            $profileGitignorePath | Should -Exist
            $profileGitignore = Get-Content -LiteralPath $profileGitignorePath -Raw
            $profileGitignore | Should -Match "(?m)^\.env\r?$"
            $profileGitignore | Should -Match "(?m)^memories/\r?$"
            $profileGitignore | Should -Match "(?m)^sessions/\r?$"
            $profileGitignore | Should -Match "(?m)^logs/\r?$"
            $profileGitignore | Should -Match "(?m)^state\.db\*\r?$"
            $profileGitignore | Should -Match "(?m)^skills/\.usage\.json\*\r?$"

            $profileDocPath = Join-Path $profileDir "docs\profile-home-layout.md"
            Test-Path -LiteralPath (Split-Path -Parent $profileDocPath) | Should -Be $true
            Test-Path -LiteralPath $profileDocPath | Should -Be $false

            $profileSoul = Get-Content -LiteralPath (Join-Path $profileDir "SOUL.md") -Raw
            $profileSoul | Should -Match "/opt/data/docs/profile-home-layout.md"
            $profileSoul | Should -Match "standard filesystem layout"
            $profileSoul | Should -Match "/opt/data/docs/slack-app-registration.md"
        }

        It 'should bootstrap shared lifelog core files, policy, cron, and first sync' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $profileDir = Join-Path $dataDir "profiles\risarisa"
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Encoding UTF8 -Value @(
                ".env",
                "profiles/"
            )
            Set-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Encoding UTF8 -Value "Default profile soul."
            Set-Content -LiteralPath (Join-Path $profileDir "SOUL.md") -Encoding UTF8 -Value "Risarisa profile soul."

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Test-Path -LiteralPath (Join-Path $dataDir "core") -PathType Container | Should -Be $true

            $rootGitignore = Get-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Raw
            $rootGitignore | Should -Match "(?m)^core/\r?$"

            $syncScriptPath = Join-Path $dataDir "scripts\lifelog_sync.sh"
            $syncScriptPath | Should -Exist
            $syncScript = Get-Content -LiteralPath $syncScriptPath -Raw
            $syncScript | Should -Match "/opt/data/core/lifelog"
            $syncScript | Should -Match "github\.com/rurusasu/lifelog\.git"
            $syncScript | Should -Match 'safe\.directory="\$LIFELOG_DIR"'
            $syncScript | Should -Match "restore_runtime_paths"
            $syncScript | Should -Match "\.direnv"
            $syncScript | Should -Match "Hermes Lifelog Sync"
            $syncScript | Should -Match "Hermes lifelog sync refused"
            $syncScript | Should -Not -Match "`r"
            $syncScript | Should -Not -Match ([string][char]7)

            $newsScriptPath = Join-Path $dataDir "scripts\article_news_slack.sh"
            $newsScriptPath | Should -Exist
            $newsScript = Get-Content -LiteralPath $newsScriptPath -Raw
            $newsScript | Should -Match "article-collector recommend all"
            $newsScript | Should -Match ([regex]::Escape('ACP_AGENT="${ARTICLE_NEWS_ACP_AGENT:-codex}"'))
            $newsScript | Should -Match ([regex]::Escape('TRANSLATE_LANG="${ARTICLE_NEWS_TRANSLATE_LANG:-ja}"'))
            $newsScript | Should -Match "C0AJVDKGN6A"
            $newsScript | Should -Match "/opt/data/core/lifelog/0_inbox/article-news"
            $newsScript | Should -Match "chat.postMessage"
            $newsScript | Should -Match "fetch_articles = true"
            $newsScript | Should -Not -Match "`r"

            $cronPath = Join-Path $dataDir "cron\jobs.json"
            $cronPath | Should -Exist
            $cron = Get-Content -LiteralPath $cronPath -Raw | ConvertFrom-Json
            $lifelogJob = @($cron.jobs | Where-Object { $_.id -eq "lifelog-core-sync" })[0]
            $lifelogJob.name | Should -Be "Daily Lifelog core GitHub sync"
            $lifelogJob.script | Should -Be "lifelog_sync.sh"
            $lifelogJob.no_agent | Should -Be $true
            $lifelogJob.schedule.expr | Should -Be "20 4 * * *"
            $newsJob = @($cron.jobs | Where-Object { $_.id -eq "article-news-slack-post" })[0]
            $newsJob.name | Should -Be "Article collector translated news Slack post"
            $newsJob.script | Should -Be "article_news_slack.sh"
            $newsJob.no_agent | Should -Be $true
            $newsJob.schedule.expr | Should -Be "0 */2 * * *"
            $newsJob.enabled | Should -Be $true

            $rootSoul = Get-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Raw
            $rootSoul | Should -Match "/opt/data/core/lifelog/AGENTS.md"
            $rootSoul | Should -Match "shared source of truth"

            $profileSoul = Get-Content -LiteralPath (Join-Path $profileDir "SOUL.md") -Raw
            $profileSoul | Should -Match "/opt/data/core/lifelog/AGENTS.md"
            $profileSoul | Should -Match "shared source of truth"

            Should -Invoke Invoke-Docker -Times 1 -ParameterFilter {
                $Arguments[0] -eq "exec" -and
                $Arguments[1] -eq "hermes" -and
                ($Arguments -join " ") -match "chown -R hermes:hermes /opt/data/core"
            }
            Should -Invoke Invoke-Docker -Times 1 -ParameterFilter {
                $Arguments[0] -eq "exec" -and
                $Arguments[1] -eq "--user" -and
                $Arguments[2] -eq "hermes" -and
                $Arguments[3] -eq "hermes" -and
                ($Arguments -join " ") -match "bash /opt/data/scripts/lifelog_sync.sh --bootstrap"
            }
        }

        It 'should update an existing lifelog cron job without removing runtime fields' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $cronDir = Join-Path $dataDir "cron"
            New-Item -ItemType Directory -Path $cronDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cronDir "jobs.json") -Encoding UTF8 -Value (@{
                    jobs       = @(
                        @{
                            id         = "lifelog-core-sync"
                            name       = "stale lifelog sync"
                            script     = "old.sh"
                            no_agent   = $false
                            schedule   = @{
                                kind    = "cron"
                                expr    = "0 0 * * *"
                                display = "0 0 * * *"
                            }
                            fire_claim = "runtime-claim"
                        },
                        @{
                            id     = "other-job"
                            name   = "Other job"
                            script = "other.sh"
                        }
                    )
                    updated_at = "2026-01-01T00:00:00Z"
                } | ConvertTo-Json -Depth 10)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $cron = Get-Content -LiteralPath (Join-Path $cronDir "jobs.json") -Raw | ConvertFrom-Json
            $lifelogJob = @($cron.jobs | Where-Object { $_.id -eq "lifelog-core-sync" })[0]
            $lifelogJob.name | Should -Be "Daily Lifelog core GitHub sync"
            $lifelogJob.script | Should -Be "lifelog_sync.sh"
            $lifelogJob.no_agent | Should -Be $true
            $lifelogJob.schedule.expr | Should -Be "20 4 * * *"
            $lifelogJob.fire_claim | Should -Be "runtime-claim"

            $otherJob = @($cron.jobs | Where-Object { $_.id -eq "other-job" })[0]
            $otherJob.name | Should -Be "Other job"
            $otherJob.script | Should -Be "other.sh"
        }

        It 'should update an existing article news cron job without removing runtime fields' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $cronDir = Join-Path $dataDir "cron"
            New-Item -ItemType Directory -Path $cronDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cronDir "jobs.json") -Encoding UTF8 -Value (@{
                    jobs       = @(
                        @{
                            id         = "article-news-slack-post"
                            name       = "stale news post"
                            script     = "old.sh"
                            no_agent   = $false
                            schedule   = @{
                                kind    = "cron"
                                expr    = "0 0 * * *"
                                display = "0 0 * * *"
                            }
                            fire_claim = "runtime-claim"
                        },
                        @{
                            id     = "other-job"
                            name   = "Other job"
                            script = "other.sh"
                        }
                    )
                    updated_at = "2026-01-01T00:00:00Z"
                } | ConvertTo-Json -Depth 10)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $cron = Get-Content -LiteralPath (Join-Path $cronDir "jobs.json") -Raw | ConvertFrom-Json
            $newsJob = @($cron.jobs | Where-Object { $_.id -eq "article-news-slack-post" })[0]
            $newsJob.name | Should -Be "Article collector translated news Slack post"
            $newsJob.script | Should -Be "article_news_slack.sh"
            $newsJob.no_agent | Should -Be $true
            $newsJob.schedule.expr | Should -Be "0 */2 * * *"
            $newsJob.fire_claim | Should -Be "runtime-claim"

            $lifelogJob = @($cron.jobs | Where-Object { $_.id -eq "lifelog-core-sync" })[0]
            $lifelogJob.script | Should -Be "lifelog_sync.sh"

            $otherJob = @($cron.jobs | Where-Object { $_.id -eq "other-job" })[0]
            $otherJob.name | Should -Be "Other job"
            $otherJob.script | Should -Be "other.sh"
        }

        It 'should skip the X API MCP server without authentication and remove the GitHub MCP server from config.yaml' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex",
                "mcp_servers:",
                "  github:",
                "    command: npx",
                '    args: ["-y", "@modelcontextprotocol/server-github"]',
                "  local:",
                "    command: local-tool"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^mcp_servers:"
            $configContent | Should -Not -Match "(?m)^\s{2}github:"
            $configContent | Should -Not -Match "@modelcontextprotocol/server-github"
            $configContent | Should -Match "(?m)^\s{2}local:"
            $configContent | Should -Not -Match "(?m)^\s{2}xapi:"
            $configContent | Should -Not -Match "/usr/local/bin/hermes-xapi-mcp"
            $configContent | Should -Match "(?m)^\s{2}x-docs:"
            $configContent | Should -Match "https://docs\.x\.com/mcp"
        }

        It 'should configure Browser MCP, preserve unrelated servers, and replace stale browser blocks' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex",
                "mcp_servers:",
                "  local:",
                "    command: local-tool",
                "  browser:",
                "    url: http://stale-browser:9000/mcp",
                "    connect_timeout: 5"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^mcp_servers:"
            $configContent | Should -Match "(?m)^\s{2}local:"
            $configContent | Should -Match "(?m)^\s{4}command:\s*local-tool"
            $configContent | Should -Match "(?m)^\s{2}browser:\r?\n\s{4}url:\s*http://browser-mcp:8080/mcp\r?\n\s{4}connect_timeout:\s*120"
            $configContent | Should -Not -Match "stale-browser"
            $configContent | Should -Not -Match "(?m)^\s{4}connect_timeout:\s*5"

            $rerunResult = $handler.Apply($ctx)

            $rerunResult.Success | Should -Be $true
            $rerunConfigContent = Get-Content -LiteralPath $configPath -Raw
            ([regex]::Matches($rerunConfigContent, "(?m)^\s{2}browser:")).Count | Should -Be 1
            $rerunConfigContent | Should -Match "(?m)^\s{2}local:"
        }

        It 'should add X docs only when mcp_servers is absent and X API authentication is unavailable' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^mcp_servers:"
            $configContent | Should -Not -Match "(?m)^\s{2}xapi:"
            $configContent | Should -Match "(?m)^\s{2}x-docs:"
        }

        It 'should remove stale X API MCP servers from managed profile configs without authentication' {
            $ctx.Options["HermesAgentManagedProfiles"] = "rick,hoffman"
            $dataDir = Join-Path $script:userProfile ".hermes"
            $profilesDir = Join-Path $dataDir "profiles"
            foreach ($profileName in @("rick", "hoffman")) {
                $profileDir = Join-Path $profilesDir $profileName
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $profileDir "config.yaml") -Encoding UTF8 -Value @(
                    "model:",
                    "  provider: openai-codex",
                    "mcp_servers:",
                    "  xapi:",
                    "    command: /usr/local/bin/hermes-xapi-mcp",
                    "    connect_timeout: 300",
                    "  local:",
                    "    command: local-tool"
                )
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            foreach ($profileName in @("rick", "hoffman")) {
                $configContent = Get-Content -LiteralPath (Join-Path $profilesDir "$profileName\config.yaml") -Raw
                $configContent | Should -Not -Match "(?m)^\s{2}xapi:"
                $configContent | Should -Not -Match "/usr/local/bin/hermes-xapi-mcp"
                $configContent | Should -Match "(?m)^\s{2}local:"
                $configContent | Should -Match "(?m)^\s{2}x-docs:"
                $configContent | Should -Match "(?m)^\s{2}browser:\r?\n\s{4}url:\s*http://browser-mcp:8080/mcp\r?\n\s{4}connect_timeout:\s*120"
            }
        }

        It 'should configure the X API MCP server when an xurl OAuth cache exists' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $cacheDir = Join-Path $configDir ".xurl"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cacheDir "oauth.json") -Encoding UTF8 -Value "{}"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^\s{2}xapi:"
            $configContent | Should -Match "(?m)^\s{4}command:\s*/usr/local/bin/hermes-xapi-mcp"
            $configContent | Should -Match "(?m)^\s{2}x-docs:"
        }

        It 'should fail before compose when Slack integration is required but unavailable' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $ctx.Options["HermesAgentRequireSlack"] = $true
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Slack"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should remove legacy plaintext dashboard auth when rotating credentials' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=old-plaintext-password",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=old-secret"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $envContent | Should -Not -Match "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="
            $envContent | Should -Not -Match "old-plaintext-password"
            $passwordContent = Get-Content -LiteralPath (Join-Path $dataDir "dashboard-basic-auth-password.txt") -Raw
            $passwordContent | Should -Match "generated-password"
        }

        It 'should return failure when password hash generation fails' {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 1
                    return @("hash failed")
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should return failure when compose up fails' {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @("generated-password", 'scrypt$hash')
                }
                $global:LASTEXITCODE = 1
                return @("compose failed")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "起動に失敗"
        }
    }
}
