# bun → pnpm + Node.js Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all bun dependencies with pnpm + Node.js across the entire dotfiles repository.

**Architecture:** Systematic file-by-file replacement. No new abstractions needed — this is a 1:1 tool swap. Each task is independent and can be executed in parallel.

**Tech Stack:** pnpm, Node.js, corepack, PowerShell, Docker, shell scripts

**Spec:** `docs/superpowers/specs/2026-03-17-bun-to-pnpm-migration-design.md`

---

### Task 1: MCP Servers — `bunx` → `pnpm dlx`

**Files:**

- Modify: `chezmoi/.chezmoidata/mcp_servers.yaml`

- [ ] **Step 1: Replace all `bunx` commands with `pnpm dlx`**

In `mcp_servers.yaml`, for each server entry that has `command: bunx`:

- Change `command: bunx` → `command: pnpm`
- Change `args: ["-y", ...]` → `args: ["dlx", ...]` (remove `-y`, keep remaining args)

Affected servers (8): context7, linear, github, deepwiki, tavily, drawio, sentry, cloud-run

Example before:

```yaml
command: bunx
args:
  - "-y"
  - "@upstash/context7-mcp@latest"
```

Example after:

```yaml
command: pnpm
args:
  - "dlx"
  - "@upstash/context7-mcp@latest"
```

- [ ] **Step 2: Verify YAML is valid**

Run: `python -c "import yaml; yaml.safe_load(open('chezmoi/.chezmoidata/mcp_servers.yaml'))"`
Expected: no error

- [ ] **Step 3: Commit**

```bash
git add chezmoi/.chezmoidata/mcp_servers.yaml
git commit -m "refactor(mcp): replace bunx with pnpm dlx in all MCP server configs"
```

---

### Task 2: Package Lists — Move bun → pnpm

**Files:**

- Move: `windows/bun/packages.json` → `windows/pnpm/packages.json`
- Move: `nix/bun/packages.json` → `nix/pnpm/packages.json`

- [ ] **Step 1: Create pnpm directories and move files**

```bash
mkdir -p windows/pnpm nix/pnpm
git mv windows/bun/packages.json windows/pnpm/packages.json
git mv nix/bun/packages.json nix/pnpm/packages.json
rmdir windows/bun nix/bun
```

- [ ] **Step 2: Update description in both files**

`windows/pnpm/packages.json`:

```json
{
  "$schema": "https://json.schemastore.org/package.json",
  "description": "pnpm global packages to install on Windows",
  "globalPackages": ["@google/gemini-cli", "@anthropic-ai/claude-code"]
}
```

`nix/pnpm/packages.json`:

```json
{
  "$schema": "https://json.schemastore.org/package.json",
  "description": "pnpm global packages to install on NixOS",
  "globalPackages": ["@google/gemini-cli", "@anthropic-ai/claude-code"]
}
```

- [ ] **Step 3: Commit**

```bash
git add windows/pnpm/ nix/pnpm/ windows/bun/ nix/bun/
git commit -m "refactor: move bun package lists to pnpm directories"
```

---

### Task 3: Invoke-ExternalCommand — Replace `Invoke-Bun` with `Invoke-Pnpm`

**Files:**

- Modify: `scripts/powershell/lib/Invoke-ExternalCommand.ps1`

- [ ] **Step 1: Replace `Invoke-Bun` with `Invoke-Pnpm`**

Replace the `Invoke-Bun` function (lines ~484-501) with:

```powershell
<#
.SYNOPSIS
    pnpm コマンドを実行する
.PARAMETER Arguments
    pnpm に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Pnpm -Arguments @("--version")
    Invoke-Pnpm -Arguments @("add", "-g", "@google/gemini-cli")
#>
function Invoke-Pnpm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )
    & pnpm @Arguments
}
```

Note: Uses direct invocation (`& pnpm @Arguments`), matching the existing pattern of `Invoke-Bun`/`Invoke-Npm`/etc.

- [ ] **Step 2: Commit**

```bash
git add scripts/powershell/lib/Invoke-ExternalCommand.ps1
git commit -m "refactor(lib): replace Invoke-Bun with Invoke-Pnpm"
```

---

### Task 4: PowerShell Handler — `Handler.Bun.ps1` → `Handler.Pnpm.ps1`

**Files:**

- Delete: `scripts/powershell/handlers/Handler.Bun.ps1`
- Create: `scripts/powershell/handlers/Handler.Pnpm.ps1`

- [ ] **Step 1: Create `Handler.Pnpm.ps1`**

Write the new handler. Key differences from BunHandler:

- Class name: `PnpmHandler`
- Name: `"Pnpm"`
- Description: `"pnpm グローバルパッケージ管理（Windows）"`
- Uses `Invoke-Pnpm` instead of `Invoke-Bun`
- `CanApply`: checks for `pnpm` command (not `bun`)
- `Apply`: uses `pnpm add -g` for install
- `IsPackageInstalled`: checks pnpm global node_modules via `pnpm root -g`
- `AddPnpmBinToPath`: adds pnpm global bin dir (output of `pnpm bin -g`) to User PATH
- Remove: `CreateBunxShim` (not needed — pnpm has `pnpm dlx` built-in)
- `EnsureGeminiCommandShim`: change `bun` → `node` in shim content
- `GetPackagesPath`: returns `windows\pnpm\packages.json`

```powershell
<#
.SYNOPSIS
    pnpm グローバルパッケージ管理ハンドラー（Windows）

.DESCRIPTION
    - pnpm add -g: パッケージリストからグローバルインストール

.NOTES
    Order = 7 (Winget/Npm の後、WSL 非依存処理)
    Mode オプションで動作を切り替え:
    - "import" (デフォルト): パッケージをインストール
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class PnpmHandler : SetupHandlerBase {
    PnpmHandler() {
        $this.Name = "Pnpm"
        $this.Description = "pnpm グローバルパッケージ管理（Windows）"
        $this.Order = 7
        $this.RequiresAdmin = $false
    }

    [bool] CanApply([SetupContext]$ctx) {
        $pnpmCmd = Get-ExternalCommand -Name "pnpm"
        if (-not $pnpmCmd) {
            $this.LogWarning("pnpm が見つかりません")
            $this.Log("インストール方法: corepack enable && corepack prepare pnpm@latest --activate", "Yellow")
            return $false
        }

        if (-not $this.TestPnpmExecutable()) {
            $this.LogWarning("pnpm が正常に動作しません")
            return $false
        }

        $packagesPath = $this.GetPackagesPath($ctx)
        if (-not (Test-PathExist -Path $packagesPath)) {
            $this.LogWarning("パッケージリストが見つかりません: $packagesPath")
            return $false
        }

        return $true
    }

    hidden [bool] TestPnpmExecutable() {
        try {
            $output = Invoke-Pnpm -Arguments @("--version")
            if ($LASTEXITCODE -eq 0 -and $output -match '\d+\.\d+') {
                return $true
            }
            return $false
        }
        catch {
            return $false
        }
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $this.AddPnpmBinToPath()

            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("pnpm グローバルパッケージをインストールしています...")
            $this.Log("ソース: $packagesPath")

            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = $packagesJson.globalPackages

            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            $failed = @()
            $succeeded = @()
            $skipped = 0

            foreach ($pkg in $packages) {
                $pkgName = $pkg -replace '@[\d\.]+$', ''
                if ($this.IsPackageInstalled($pkgName)) {
                    $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                    $skipped++
                    continue
                }

                $this.Log("インストール中: $pkg")
                Invoke-Pnpm -Arguments @("add", "-g", $pkg) | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    $succeeded += $pkg
                    $this.Log("✓ $pkg", "Green")
                }
                else {
                    $failed += $pkg
                    $this.LogWarning("✗ $pkg のインストールに失敗しました")
                }
            }

            $this.EnsureGeminiCommandShim()

            if ($failed.Count -eq 0) {
                return $this.CreateSuccessResult("$($succeeded.Count) 個インストール, $skipped 個スキップ")
            }
            else {
                return $this.CreateSuccessResult("$($succeeded.Count) 個成功, $($failed.Count) 個失敗, $skipped 個スキップ")
            }
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [bool] IsPackageInstalled([string]$pkgName) {
        try {
            $globalRoot = Invoke-Pnpm -Arguments @("root", "-g")
            if ($LASTEXITCODE -ne 0 -or -not $globalRoot) { return $false }
            $globalRoot = $globalRoot.Trim()
            $pkgPath = Join-Path $globalRoot $pkgName
            return (Test-Path -LiteralPath $pkgPath -PathType Container)
        }
        catch {
            return $false
        }
    }

    hidden [void] AddPnpmBinToPath() {
        try {
            $pnpmBinPath = (Invoke-Pnpm -Arguments @("bin", "-g")).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $pnpmBinPath) {
                $this.Log("pnpm グローバル bin パスを取得できません", "Gray")
                return
            }

            if (-not (Test-Path $pnpmBinPath)) {
                New-Item -ItemType Directory -Path $pnpmBinPath -Force | Out-Null
            }

            $userPath = Get-UserEnvironmentPath
            $pathItems = if ($userPath) { $userPath -split ";" } else { @() }

            if ($pathItems -contains $pnpmBinPath) {
                $this.Log("pnpm bin は既に PATH に含まれています", "Gray")
                return
            }

            $newPath = ($pnpmBinPath, $userPath | Where-Object { $_ }) -join ";"
            Set-UserEnvironmentPath -Path $newPath
            $this.Log("pnpm bin を USER PATH に追加しました: $pnpmBinPath", "Green")
            $this.Log("ターミナルを再起動すると claude / gemini コマンドが使えます", "Gray")
        }
        catch {
            $this.Log("pnpm bin パスの追加に失敗しました: $($_.Exception.Message)", "Yellow")
        }
    }

    hidden [void] EnsureGeminiCommandShim() {
        try {
            $globalRoot = (Invoke-Pnpm -Arguments @("root", "-g")).Trim()
        }
        catch {
            return
        }
        if ($LASTEXITCODE -ne 0 -or -not $globalRoot) { return }

        $entrypoint = Join-Path $globalRoot "@google\gemini-cli\dist\index.js"
        if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
            $this.Log("Gemini CLI のエントリポイントが見つからないため shim 作成をスキップします", "Gray")
            return
        }

        if ($this.TestGeminiCommand()) {
            $this.Log("gemini コマンドは正常です。shim 作成は不要です", "Gray")
            return
        }

        $localBin = Join-Path $env:USERPROFILE ".local\bin"
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null

        $shimPath = Join-Path $localBin "gemini.cmd"
        $shimContent = @(
            "@echo off"
            "setlocal"
            "for /f ""delims="" %%i in ('pnpm root -g') do set ""PNPM_GLOBAL=%%i"""
            "set ""GEMINI_JS=%PNPM_GLOBAL%\@google\gemini-cli\dist\index.js"""
            "if not exist ""%GEMINI_JS%"" ("
            "  echo [ERROR] Gemini CLI entrypoint not found: %GEMINI_JS%"
            "  exit /b 1"
            ")"
            "node ""%GEMINI_JS%"" %*"
            "exit /b %ERRORLEVEL%"
            ""
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($shimPath, $shimContent, [System.Text.Encoding]::ASCII)

        $this.PrependUserPath($localBin)
        $this.Log("gemini.cmd shim を作成しました: $shimPath", "Green")
        $this.Log("Windows では ~/.local/bin/gemini.cmd を優先して実行します", "Gray")
    }

    hidden [bool] TestGeminiCommand() {
        try {
            $output = & gemini --version 2>&1
            return ($LASTEXITCODE -eq 0 -and ($output -match '\d+\.\d+'))
        }
        catch {
            return $false
        }
    }

    hidden [void] PrependUserPath([string]$pathToPrepend) {
        $userPath = Get-UserEnvironmentPath
        $items = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        $items = @($items | Where-Object { $_ -ne $pathToPrepend })
        $newPath = (@($pathToPrepend) + $items) -join ";"
        Set-UserEnvironmentPath -Path $newPath

        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        if (-not ($processItems -contains $pathToPrepend)) {
            $env:PATH = "$pathToPrepend;$env:PATH"
        }
    }

    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\pnpm\packages.json"
    }
}
```

- [ ] **Step 2: Delete old handler**

```bash
git rm scripts/powershell/handlers/Handler.Bun.ps1
```

- [ ] **Step 3: Commit**

```bash
git add scripts/powershell/handlers/Handler.Pnpm.ps1
git commit -m "refactor(handler): replace BunHandler with PnpmHandler"
```

---

### Task 5: PowerShell Handler Tests — `Handler.Bun.Tests.ps1` → `Handler.Pnpm.Tests.ps1`

**Files:**

- Delete: `scripts/powershell/tests/handlers/Handler.Bun.Tests.ps1`
- Create: `scripts/powershell/tests/handlers/Handler.Pnpm.Tests.ps1`

- [ ] **Step 1: Create `Handler.Pnpm.Tests.ps1`**

Mirror the existing test structure but adapted for PnpmHandler:

- Source `Handler.Pnpm.ps1` instead of `Handler.Bun.ps1`
- Class: `PnpmHandler`
- Mock `Invoke-Pnpm` instead of `Invoke-Bun`
- Mock `Get-ExternalCommand -Name "pnpm"` instead of `"bun"`
- Constructor tests: Name="Pnpm", Order=7
- Remove tests for `CreateBunxShim` and `AddBunBinToPath`
- Add tests for `AddPnpmBinToPath` (mocks `Invoke-Pnpm -Arguments @("bin", "-g")`)
- Update `IsPackageInstalled` tests to mock `Invoke-Pnpm -Arguments @("root", "-g")`
- Update `EnsureGeminiCommandShim` tests: entrypoint path uses pnpm root, shim uses `node` not `bun`

- [ ] **Step 2: Delete old test file**

```bash
git rm scripts/powershell/tests/handlers/Handler.Bun.Tests.ps1
```

- [ ] **Step 3: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/powershell/tests/handlers/Handler.Pnpm.Tests.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add scripts/powershell/tests/handlers/Handler.Pnpm.Tests.ps1
git commit -m "test(handler): replace BunHandler tests with PnpmHandler tests"
```

---

### Task 6: PowerShell Profile — Replace bun shims

**Files:**

- Modify: `chezmoi/shells/Microsoft.PowerShell_profile.ps1`

- [ ] **Step 1: Replace bun CLI shims section (lines 130-147)**

Replace the entire block from `# bun global CLI shims` to the `Remove-Variable` line:

```powershell
# pnpm global CLI shims
# pnpm's global bin may not be in PATH yet, or Windows shims may not pass env vars.
# Define PowerShell functions that call node + entrypoint directly.
$_pnpmGlobalRoot = $null
try {
    $_pnpmGlobalRoot = (& pnpm root -g 2>$null)
    if ($_pnpmGlobalRoot) { $_pnpmGlobalRoot = $_pnpmGlobalRoot.Trim() }
} catch {}
if ($_pnpmGlobalRoot -and (Test-Path $_pnpmGlobalRoot)) {
    $_pnpmCliShims = @{
        claude = "@anthropic-ai\claude-code\cli.js"
        gemini = "@google\gemini-cli\dist\index.js"
    }
    foreach ($_entry in $_pnpmCliShims.GetEnumerator()) {
        $_entrypoint = Join-Path $_pnpmGlobalRoot $_entry.Value
        if (Test-Path -LiteralPath $_entrypoint -PathType Leaf) {
            $__ep = $_entrypoint
            New-Item -Path "Function:\Global:$($_entry.Key)" -Value (
                [scriptblock]::Create("& node `"$__ep`" @args")
            ) -Force | Out-Null
        }
    }
}
Remove-Variable _pnpmGlobalRoot, _pnpmCliShims, _entry, _entrypoint, __ep -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Update comment on line 115**

Change:

```powershell
# Set it at session level so ALL child processes (bun, node, etc.) inherit it.
```

To:

```powershell
# Set it at session level so ALL child processes (node, pnpm, etc.) inherit it.
```

- [ ] **Step 3: Commit**

```bash
git add chezmoi/shells/Microsoft.PowerShell_profile.ps1
git commit -m "refactor(profile): replace bun CLI shims with pnpm/node shims"
```

---

### Task 7: Docker — Dockerfile

**Files:**

- Modify: `docker/openclaw/Dockerfile`

- [ ] **Step 1: Remove bun install and replace with pnpm via corepack (lines 30-33)**

Replace:

```dockerfile
# Install bun for runtime skills while keeping Node/npm as primary runtime.
ENV BUN_INSTALL=/home/bun/.bun
RUN mkdir -p /home/bun \
    && curl -fsSL https://bun.sh/install | bash
```

With:

```dockerfile
# Enable pnpm via corepack (ships with Node.js 22).
RUN corepack enable && corepack prepare pnpm@latest --activate \
    && mkdir -p /home/app
```

- [ ] **Step 2: Update ENV block (lines 35-41)**

Replace:

```dockerfile
ENV NODE_ENV=production \
    HOME=/home/bun \
    ...
    PATH=/home/bun/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

With:

```dockerfile
ENV NODE_ENV=production \
    HOME=/home/app \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_LOGLEVEL=warn \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

- [ ] **Step 3: Replace qmd install (lines 51-56)**

Replace:

```dockerfile
RUN bun install -g --trust https://github.com/tobi/qmd \
    && cd /home/bun/.bun/install/global/node_modules/@tobilu/qmd \
    && bun install --frozen-lockfile \
    && bun run build
```

With:

```dockerfile
# QMD: local hybrid search engine for memory (BM25 + vector via GGUF models).
# Clone from GitHub and build with pnpm since it's not published to npm.
RUN git clone --depth 1 https://github.com/tobi/qmd /opt/qmd \
    && cd /opt/qmd \
    && pnpm install --frozen-lockfile \
    && pnpm run build \
    && pnpm link --global
```

- [ ] **Step 4: Update directory creation (lines 63-66)**

Replace all `/home/bun` with `/home/app`:

```dockerfile
RUN mkdir -p /app/data/workspace \
    && mkdir -p /home/app/.openclaw /home/app/.gemini /home/app/.acpx /home/app/.claude \
    && chmod +x /usr/local/bin/openclaw-entrypoint.sh \
    && chown -R 1000:1000 /app/data /home/app
```

(Remove `/home/bun/.bun` and `/app/data/.bun` directories — no longer needed)

- [ ] **Step 5: Commit**

```bash
git add docker/openclaw/Dockerfile
git commit -m "refactor(docker): replace bun with pnpm via corepack, rename /home/bun to /home/app"
```

---

### Task 8: Docker — docker-compose.yml

**Files:**

- Modify: `docker/openclaw/docker-compose.yml`

- [ ] **Step 1: Replace all `/home/bun` with `/home/app`**

All volume mounts, tmpfs, environment vars referencing `/home/bun`.

- [ ] **Step 2: Update environment section**

- Change `HOME: /home/bun` → `HOME: /home/app`
- Remove `BUN_INSTALL: /app/data/.bun` and its comment (`# Runtime bun installs (skills) go to the writable data volume`)
- Change PATH to remove bun paths:

  ```yaml
  PATH: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  ```

- [ ] **Step 3: Update volume mounts**

- `openclaw-home:/home/bun/.openclaw` → `openclaw-home:/home/app/.openclaw`
- `openclaw-acpx:/home/bun/.acpx` → `openclaw-acpx:/home/app/.acpx`
- `${GEMINI_CREDENTIALS_DIR:-gemini-credentials}:/home/bun/.gemini` → `...:/home/app/.gemini`
- `${CLAUDE_CREDENTIALS_DIR:-claude-credentials}:/home/bun/.claude` → `...:/home/app/.claude`
- `${CLAUDE_CONFIG_JSON:-/dev/null}:/home/bun/.claude.json:ro` → `...:/home/app/.claude.json:ro`

- [ ] **Step 4: Update tmpfs**

- `/home/bun/.agents` → `/home/app/.agents`

- [ ] **Step 5: Commit**

```bash
git add docker/openclaw/docker-compose.yml
git commit -m "refactor(docker): update docker-compose for /home/app and remove bun env vars"
```

---

### Task 9: Docker — entrypoint.sh

**Files:**

- Modify: `docker/openclaw/entrypoint.sh`

- [ ] **Step 1: Replace all `/home/bun` with `/home/app`**

Affected lines: 39, 54-57, 62-66, 69-76, 78, 215-216, and any others.

Global search-replace: `/home/bun` → `/home/app`

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "refactor(docker): update entrypoint.sh paths from /home/bun to /home/app"
```

---

### Task 10: NixRebuild Handler — `InstallBunGlobalPackages` → `InstallPnpmGlobalPackages`

**Files:**

- Modify: `scripts/powershell/handlers/Handler.NixRebuild.ps1`

- [ ] **Step 1: Rename method and update all bun references**

In `Handler.NixRebuild.ps1`:

- Rename `InstallBunGlobalPackages` → `InstallPnpmGlobalPackages`
- Update description comment (line 8): `bun グローバルパッケージ` → `pnpm グローバルパッケージ`
- Line 78: `"bun パッケージ設定が..."` → `"pnpm パッケージ設定が..."`
- Line 85: `"インストールする bun パッケージがありません"` → `"インストールする pnpm パッケージがありません"`
- Line 92: `"bun pm ls -g 2>/dev/null"` → `"pnpm ls -g --depth=0 2>/dev/null"`
- Line 107: `"bun グローバルパッケージはすべて..."` → `"pnpm グローバルパッケージはすべて..."`
- Line 112: `"bun グローバルパッケージをインストールしています"` → `"pnpm グローバルパッケージをインストールしています"`
- Line 116: `"bun install -g $pkgList"` → `"pnpm add -g $pkgList"`
- Lines 126, 129: Update log messages from `bun` → `pnpm`
- Line 133: `"bun パッケージインストール中に..."` → `"pnpm パッケージインストール中に..."`
- Line 159: `"nix\bun\packages.json"` → `"nix\pnpm\packages.json"`
- Line 160: `$this.InstallBunGlobalPackages(...)` → `$this.InstallPnpmGlobalPackages(...)`

- [ ] **Step 2: Update NixRebuild tests**

In `scripts/powershell/tests/handlers/Handler.NixRebuild.Tests.ps1`:

- Update all mocks and assertions referencing `bun` commands to `pnpm`
- Update path references from `nix\bun\packages.json` to `nix\pnpm\packages.json`
- Update any `Invoke-Bun` mocks to `Invoke-Pnpm`

- [ ] **Step 3: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester scripts/powershell/tests/handlers/Handler.NixRebuild.Tests.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add scripts/powershell/handlers/Handler.NixRebuild.ps1 scripts/powershell/tests/handlers/Handler.NixRebuild.Tests.ps1
git commit -m "refactor(handler): migrate NixRebuild handler from bun to pnpm"
```

---

### Task 11: OpenClaw Handler — Update Docker paths

**Files:**

- Modify: `scripts/powershell/handlers/Handler.OpenClaw.ps1`

- [ ] **Step 1: Replace `/home/bun` with `/home/app` in Docker exec commands**

Lines 378, 385, 386: Replace `//home/bun/` → `//home/app/` in the Docker exec/cp commands:

```powershell
# Line 378
$existing = Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "test -f //home/app/.openclaw/cron/jobs.json && echo exists"
# Line 385
Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "mkdir -p //home/app/.openclaw/cron"
# Line 386
Invoke-Docker "cp" ($seedFile -replace '\\', '/') "openclaw://home/app/.openclaw/cron/jobs.json"
```

- [ ] **Step 2: Commit**

```bash
git add scripts/powershell/handlers/Handler.OpenClaw.ps1
git commit -m "refactor(handler): update OpenClaw handler Docker paths from /home/bun to /home/app"
```

---

### Task 12: Nix — Remove bun from system packages

**Files:**

- Modify: `nix/modules/host/default.nix`

- [ ] **Step 1: Remove `bun` from packages list (line 71)**

Remove the `bun` entry from the Nix system packages. pnpm will be available via corepack (ships with nodejs_22).

If there is a comment like `# JavaScript runtime (for claude-code, gemini-cli, openclaw)`, update it to reflect that pnpm is used via corepack:

```nix
# JavaScript runtime (for claude-code, gemini-cli, openclaw — pnpm via corepack)
nodejs_22 # openclaw requires Node.js 22+
```

- [ ] **Step 2: Commit**

```bash
git add nix/modules/host/default.nix
git commit -m "refactor(nix): remove bun from system packages, pnpm available via corepack"
```

---

### Task 13: Taskfile — Remove bun references

**Files:**

- Modify: `Taskfile.yml`

- [ ] **Step 1: Remove `INSTALL_BUN=1` from sandbox build (line 143)**

Change:

```yaml
--build-arg INSTALL_BUN=1
```

To: remove this line entirely (or set to `--build-arg INSTALL_BUN=0`)

- [ ] **Step 2: Remove bun cache from sandbox:cache-init (line 204)**

Remove `/app/data/workspace/.cache/bun` from the `mkdir -p` command.

- [ ] **Step 3: Remove bun cache from sandbox:cache-clean (line 214)**

Remove `/app/data/workspace/.cache/bun` from the `rm -rf` command.

- [ ] **Step 4: Commit**

```bash
git add Taskfile.yml
git commit -m "refactor(taskfile): remove bun references from sandbox tasks"
```

---

### Task 14: Shell Script — Update tool check

**Files:**

- Modify: `check_nixos.sh`

- [ ] **Step 1: Replace `bun` with `pnpm` in tool check list (line 11)**

Change:

```bash
for t in fzf eza zoxide rg fd starship git gh nvim task bun claude gemini uv zsh pwsh; do
```

To:

```bash
for t in fzf eza zoxide rg fd starship git gh nvim task pnpm claude gemini uv zsh pwsh; do
```

- [ ] **Step 2: Commit**

```bash
git add check_nixos.sh
git commit -m "refactor: replace bun with pnpm in NixOS tool check"
```

---

### Task 15: Docker — README.md path updates

**Files:**

- Modify: `docker/openclaw/README.md`

- [ ] **Step 1: Replace all `/home/bun` with `/home/app`**

Global search-replace throughout the file.

- [ ] **Step 2: Remove any bun-specific references**

Update any mentions of bun install paths, BUN_INSTALL env var, `/app/data/.bun` (skill runtime install path), etc.

- [ ] **Step 3: Commit**

```bash
git add docker/openclaw/README.md
git commit -m "docs(openclaw): update paths from /home/bun to /home/app"
```

---

### Task 16: Final Verification

- [ ] **Step 1: Search for remaining bun references**

Run: `grep -ri "bun" --include="*.ps1" --include="*.yaml" --include="*.yml" --include="*.json" --include="*.sh" --include="Dockerfile*" --include="*.md" .`

Verify no unintended bun references remain (some may be legitimate, e.g., "bundle" in other contexts).

- [ ] **Step 2: Run PowerShell tests**

Run: `task test`
Expected: All tests pass

- [ ] **Step 3: Verify Docker build**

Run: `docker build -t local/openclaw:test -f docker/openclaw/Dockerfile docker/openclaw/`
Expected: Build succeeds

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "refactor: complete bun to pnpm migration"
```
