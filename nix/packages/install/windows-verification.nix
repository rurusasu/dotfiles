# Windows CLI and desktop installation verification contracts.
{ packageInstallTimeoutSeconds }:
{
  # Post-install verification commands for winget packages.
  # Keys match catalog attr names. GUI-only packages are omitted.
  wingetVerify = {
    glazewm = {
      command = "glazewm";
      args = [ "--version" ];
    };
    chezmoi = {
      command = "chezmoi";
      args = [ "--version" ];
    };
    git = {
      command = "git";
      args = [ "--version" ];
    };
    gh = {
      command = "gh";
      args = [ "--version" ];
      timeoutSeconds = 60;
    };
    fd = {
      command = "fd";
      args = [ "--version" ];
    };
    ripgrep = {
      command = "rg";
      args = [ "--version" ];
    };
    jq = {
      command = "jq";
      args = [ "--version" ];
    };
    eza = {
      command = "eza";
      args = [ "--version" ];
    };
    zoxide = {
      command = "zoxide";
      args = [ "--version" ];
    };
    fzf = {
      command = "fzf";
      args = [ "--version" ];
    };
    direnv = {
      command = "direnv";
      args = [ "--version" ];
    };
    starship = {
      command = "starship";
      args = [ "--version" ];
    };
    nodejs = {
      command = "node";
      args = [ "--version" ];
    };
    uv = {
      command = "uv";
      args = [ "--version" ];
    };
    _1password-cli = {
      command = "op";
      args = [ "--version" ];
    };
    powershell = {
      command = "pwsh";
      args = [ "--version" ];
    };
    go-task = {
      command = "task";
      args = [ "--version" ];
    };
    go = {
      command = "go";
      args = [ "version" ];
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
    rustup = {
      command = "rustup";
      args = [ "--version" ];
    };
    ghq = {
      command = "ghq";
      args = [ "--version" ];
    };
    lazygit = {
      command = "lazygit";
      args = [ "--version" ];
    };
    imagemagick = {
      command = "magick";
      args = [ "--version" ];
    };
    poppler-utils = {
      command = "pdftoppm";
      args = [ "-v" ];
    };
    tree-sitter = {
      command = "tree-sitter";
      args = [ "--version" ];
    };
    ollama = {
      command = "ollama";
      args = [ "--version" ];
    };
    google-cloud-sdk = {
      command = "gcloud";
      args = [ "version" ];
    };
  };

  # Post-install verification commands for Windows-only winget packages.
  # Keys match PackageIdentifier values because these packages have no catalog attr.
  wingetVerifyById = {
    "AgileBits.1Password" = {
      type = "windowsInstalledProduct";
      command = "AgileBits.1Password";
      appxPackage = {
        name = "AgileBits.1Password";
        packageFamilyName = "Agilebits.1Password_amwd9z03whsfe";
        executable = "1Password.exe";
      };
      uninstallEntry = {
        displayName = "1Password";
        executablePaths = [
          "%ProgramFiles%\\1Password\\1Password.exe"
          "%LOCALAPPDATA%\\1Password\\app\\*\\1Password.exe"
        ];
      };
    };
    "TheBrowserCompany.Arc" = {
      type = "appxLaunchTarget";
      command = "TheBrowserCompany.Arc";
      args = [ "TheBrowserCompany.Arc_ttt1ap7aakyb4!Arc" ];
    };
    "AutoHotkey.AutoHotkey" = {
      type = "windowsInstalledProduct";
      command = "AutoHotkey";
      uninstallEntry = {
        productCodes = [ "AutoHotkey" ];
        displayName = "AutoHotkey";
        executablePaths = [ "%ProgramFiles%\\AutoHotkey\\v2\\AutoHotkey.exe" ];
      };
    };
    "Discord.Discord" = {
      type = "windowsInstalledProduct";
      command = "Discord";
      uninstallEntry = {
        productCodes = [ "Discord" ];
        displayName = "Discord";
        publisher = "Discord Inc.";
        executablePaths = [ "%LOCALAPPDATA%\\Discord\\app-*\\Discord.exe" ];
      };
    };
    "Docker.DockerDesktop" = {
      type = "windowsInstalledProduct";
      command = "Docker Desktop";
      uninstallEntry = {
        displayName = "Docker Desktop";
        publisher = "Docker Inc.";
        executablePaths = [
          "%ProgramFiles%\\Docker\\Docker\\Docker Desktop.exe"
          "%LOCALAPPDATA%\\Programs\\DockerDesktop\\Docker Desktop.exe"
        ];
      };
    };
    "dprint.dprint" = {
      command = "dprint";
      args = [ "--version" ];
    };
    "Google.Chrome" = {
      type = "windowsInstalledProduct";
      command = "Google Chrome";
      uninstallEntry = {
        displayName = "Google Chrome";
        publisher = "Google LLC";
        executablePaths = [
          "%ProgramFiles%\\Google\\Chrome\\Application\\chrome.exe"
          "%ProgramFiles(x86)%\\Google\\Chrome\\Application\\chrome.exe"
          "%LOCALAPPDATA%\\Google\\Chrome\\Application\\chrome.exe"
        ];
      };
    };
    "hadolint.hadolint" = {
      command = "hadolint";
      args = [ "--version" ];
    };
    "Obsidian.Obsidian" = {
      type = "windowsInstalledProduct";
      command = "Obsidian";
      uninstallEntry = {
        productCodes = [ "bd400747-f0c1-5638-a859-982036102edf" ];
        displayName = "Obsidian";
        executablePaths = [
          "%LOCALAPPDATA%\\Programs\\Obsidian\\Obsidian.exe"
          "%ProgramFiles%\\Obsidian\\Obsidian.exe"
        ];
      };
    };
    "Microsoft.WSL" = {
      command = "wsl";
      args = [ "--version" ];
      timeoutSeconds = 120;
      recoveryStrategy = "wingetRepairThenReinstall";
    };
    "Oven-sh.Bun" = {
      command = "bun";
      args = [ "--version" ];
    };
    "Microsoft.PowerToys" = {
      type = "windowsInstalledProduct";
      command = "Microsoft PowerToys";
      uninstallEntry = {
        displayNamePattern = "^PowerToys(?: \\(Preview\\))?$";
        publisher = "Microsoft Corporation";
        executablePaths = [
          "%ProgramFiles%\\PowerToys\\PowerToys.exe"
          "%LOCALAPPDATA%\\PowerToys\\PowerToys.exe"
        ];
      };
    };
    "Microsoft.VCRedist.2015+.x64" = {
      type = "windowsInstalledProduct";
      command = "Microsoft Visual C++ 2015-2022 Redistributable (x64)";
      uninstallEntry = {
        displayNamePattern = "^Microsoft Visual C\\+\\+ (?:2015-2022 Redistributable|v14 Redistributable) \\(x64\\)";
        publisher = "Microsoft Corporation";
        executablePaths = [ "%SystemRoot%\\System32\\vcruntime140.dll" ];
      };
    };
    "Microsoft.VisualStudio.2022.BuildTools" = {
      type = "visualStudioInstanceVersion";
      command = "Microsoft.VisualStudio.Product.BuildTools";
      productId = "Microsoft.VisualStudio.Product.BuildTools";
      minimumVersion = "17.0";
      requiredComponent = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64";
      compilerRelativePath = "VC\\Tools\\MSVC\\*\\bin\\Hostx64\\x64\\cl.exe";
    };
    "Microsoft.WindowsTerminal" = {
      type = "appxLaunchTarget";
      command = "Microsoft.WindowsTerminal";
      args = [ "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" ];
    };
    "StablyAI.Orca" = {
      type = "windowsInstalledProduct";
      command = "OrcaSlicer";
      uninstallEntry = {
        productCodes = [ "2b325ec9-0ed1-575f-ad70-e08307aee879" ];
        displayName = "Orca";
      };
    };
    "zig.zig" = {
      command = "zig";
      args = [ "version" ];
    };
  };

  # Post-install verification commands for Windows-only Microsoft Store packages.
  # Keys match Microsoft Store Product ID values because these packages have no catalog attr.
  msstoreVerifyById = {
    "9PLM9XGG6VKS" = {
      type = "appxLaunchTarget";
      command = "OpenAI.Codex";
      args = [ "OpenAI.Codex_2p2nqsd0c76g0!App" ];
    };
  };

}
