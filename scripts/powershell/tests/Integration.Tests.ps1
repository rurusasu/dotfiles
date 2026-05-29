#Requires -Module Pester

Describe 'Integration Verification - Windows Environment' {
    Context 'GUI Apps Installation' {
        It "should have <_> installed" -ForEach @(
            'Obsidian.Obsidian'
        ) {
            $result = & winget list --id $_ --accept-source-agreements 2>$null
            if ($LASTEXITCODE -ne 0) { throw "winget パッケージ '$_' がインストールされていません" }
            Write-Host "確認完了: '$_'"
        }
    }

    Context 'Dev Tools Installation' {
        It "should have <_> installed" -ForEach @(
            'gh'
            'rg'
            'fd'
            'eza'
            'fzf'
            'zoxide'
            'winget'
            'wezterm'
        ) {
            $c = Get-Command -Name $_ -ErrorAction SilentlyContinue
            if ($null -eq $c) { throw "コマンド '$_' が見つかりません" }
            Write-Host "確認完了: '$_'"
        }
    }

    Context 'NixOS Verification' {
        BeforeAll {
            $script:nixosAvailable = $false
            try {
                $distros = & wsl --list --quiet 2>$null
                if ($LASTEXITCODE -eq 0 -and ($distros -match 'NixOS')) {
                    $script:nixosAvailable = $true
                }
            } catch { }
        }

        It "should have <_> installed in NixOS" -ForEach @(
            'nvim'
            'zed'
            'task'
            'op'
            'obsidian'
        ) {
            if (-not $script:nixosAvailable) {
                Set-ItResult -Skipped -Because "NixOS ディストリビューションが利用できません"
            }
            $output = & wsl -d NixOS -- bash -lc "command -v $_"
            if ($LASTEXITCODE -ne 0) { throw "NixOS: '$_' が見つかりません" }
            Write-Host "NixOS: 確認完了 '$_' 場所: '$output'"
        }
    }

    Context 'Neovim PATH Dependencies (options.lua glob patterns)' {
        It "should find magick.exe via ImageMagick glob" {
            # options.lua: vim.fn.glob("C:/Program Files/ImageMagick*")
            $dirs = @(Get-Item "C:/Program Files/ImageMagick*" -ErrorAction SilentlyContinue)
            $found = $dirs | Where-Object { Test-Path (Join-Path $_.FullName "magick.exe") }
            if (-not $found) {
                throw "magick.exe が見つかりません。ImageMagick をインストールしてください: winget install ImageMagick.ImageMagick"
            }
            Write-Host "確認完了: magick.exe @ $($found[0].FullName)"
        }

        It "should find pdftoppm.exe via Poppler glob" {
            # options.lua: vim.fn.glob("$LOCALAPPDATA/Microsoft/WinGet/Packages/oschwartz10612.Poppler*/*/Library/bin")
            $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
            $pattern = Join-Path $localAppData "Microsoft/WinGet/Packages/oschwartz10612.Poppler*/*/Library/bin"
            $dirs = @(Get-Item $pattern -ErrorAction SilentlyContinue)
            $found = $dirs | Where-Object { Test-Path (Join-Path $_.FullName "pdftoppm.exe") }
            if (-not $found) {
                throw "pdftoppm.exe が見つかりません。Poppler をインストールしてください: winget install oschwartz10612.Poppler"
            }
            Write-Host "確認完了: pdftoppm.exe @ $($found[0].FullName)"
        }
    }

    Context 'Font Installation' {
        It "should have UDEV Gothic NF font installed" {
            # GDI キャッシュ（InstalledFontCollection）はセッション再起動後に更新されるため
            # レジストリを直接確認する（インストール直後でも信頼性が高い）
            $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            $key = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($null -eq $key) { throw "フォント 'UDEVGothic NF' がインストールされていません。chezmoi apply を実行してください。" }
            $found = @($key.PSObject.Properties | Where-Object { $_.Name -like "UDEVGothic*NF*" })
            if ($found.Count -eq 0) {
                throw "フォント 'UDEVGothic NF' がインストールされていません。chezmoi apply を実行してください。"
            }
            Write-Host "確認完了: フォント '$($found[0].Name)' がインストール済み ($($found.Count) 件)"
        }
    }
}
