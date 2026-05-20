# Creates a directory junction so Windows neovim finds config deployed by chezmoi.
# chezmoi deploys dot_config/nvim to %USERPROFILE%\.config\nvim (Linux-style home).
# neovim on Windows expects config at %LOCALAPPDATA%\nvim, so we junction it there.
$target = "$env:USERPROFILE\.config\nvim"
$link = "$env:LOCALAPPDATA\nvim"

if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq "Junction") {
        Remove-Item $link -Force
    } else {
        Write-Error "$link exists and is not a junction. Remove it manually."
        exit 1
    }
}

New-Item -ItemType Junction -Path $link -Target $target | Out-Null
Write-Host "Created junction: $link -> $target"
