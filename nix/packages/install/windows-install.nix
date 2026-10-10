# Windows installer policy, direct downloads, PATH, and portable links.
{ packageInstallTimeoutSeconds }:
{
  # Extra winget install arguments for packages that need a specific installer.
  wingetInstallArgs = {
    glazewm = [
      "--scope"
      "machine"
    ];
    chezmoi = [
      "--scope"
      "user"
    ];
    direnv = [
      "--scope"
      "user"
    ];
    dprint = [
      "--scope"
      "user"
    ];
    "eza-community.eza" = [
      "--scope"
      "user"
    ];
    autohotkey = [
      "--scope"
      "machine"
    ];
    "Microsoft.VisualStudio.2022.BuildTools" = [
      "--override"
      "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart"
    ];
    powershell = [
      "--installer-type"
      "wix"
    ];
    fd = [
      "--scope"
      "user"
    ];
    "sharkdp.fd" = [
      "--scope"
      "user"
    ];
  };

  # Packages that must be installed from the elevated Windows phase. Keeping
  # this metadata in the catalog prevents the non-elevated user phase from
  # accidentally passing machine-scope installers to winget.
  wingetRequiresAdmin = {
    glazewm = true;
    autohotkey = true;
    "Microsoft.VisualStudio.2022.BuildTools" = true;
  };

  # One install timeout shared by every package adapter. Per-package entries
  # remain supported for exceptional cases; only intentional WinGet entries
  # are emitted into the generated catalog so runtime environment overrides
  # remain effective for the generic case.
  inherit packageInstallTimeoutSeconds;
  wingetInstallTimeoutSeconds = { };

  wingetDirectInstallers = {
    chezmoi = {
      type = "archive";
      url = "https://github.com/twpayne/chezmoi/releases/download/v2.72.2/chezmoi_2.72.2_windows_amd64.zip";
      sha256 = "5c2038736c485d4e3eaad4ac06ea1fe3c4b63d4d51e470547bf12737c02f37f6";
      destination = "%LOCALAPPDATA%\\Programs\\chezmoi";
      executable = "chezmoi.exe";
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
    direnv = {
      type = "file";
      url = "https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.windows-amd64";
      sha256 = "d96fc8b7cf020c2d4c1dbbc2ccec5fd1cab05b51c491f02c8527a7fa6c50a1cd";
      destination = "%LOCALAPPDATA%\\Programs\\direnv";
      executable = "direnv.exe";
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
    dprint = {
      type = "archive";
      url = "https://github.com/dprint/dprint/releases/download/0.57.4/dprint-x86_64-pc-windows-msvc.zip";
      sha256 = "1038af32fade7a79f9c3a690d9546bb17be13dd7b4568a3684692fdcb0a52a1d";
      destination = "%LOCALAPPDATA%\\Programs\\dprint";
      executable = "dprint.exe";
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
    fd = {
      type = "archive";
      url = "https://github.com/sharkdp/fd/releases/download/v10.5.0/fd-v10.5.0-x86_64-pc-windows-msvc.zip";
      sha256 = "a227701b8551c35a9931d9f6da75503cf86d88e182d71fb849a70864c5d57cd7";
      destination = "%LOCALAPPDATA%\\Programs\\fd";
      executable = "fd-v10.5.0-x86_64-pc-windows-msvc\\fd.exe";
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
    "eza-community.eza" = {
      type = "archive";
      url = "https://github.com/eza-community/eza/releases/download/v0.23.5/eza.exe_x86_64-pc-windows-gnu.zip";
      sha256 = "c830638c844a5b89d39ba662b5549903a71fa539018e813880f5b8afa77bac2e";
      destination = "%LOCALAPPDATA%\\Programs\\eza";
      executable = "eza.exe";
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
  };

  # Packages kept in the catalog but skipped by the normal Windows installer.
  wingetSkipInstall = { };

  # Upstream installers and Microsoft Store installs can drift, require
  # elevation, or hang in CI. Avoid making CI depend on their live behavior.
  wingetCiSkipInstall = {
    google-cloud-sdk = true;
    "StablyAI.Orca" = true;
  };

  # Extra PATH directories for installers that do not register CLI commands on PATH.
  # Entries may contain Windows environment variables and glob wildcards.
  wingetPathEntries = {
    glazewm = [ "%ProgramFiles%\\glzr.io\\GlazeWM" ];
    nodejs = [ "%ProgramFiles%\\nodejs" ];
    "Task.Task" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Task.Task*" ];
    "hadolint.hadolint" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\hadolint.hadolint*" ];
    "tree-sitter.tree-sitter-cli" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tree-sitter.tree-sitter-cli*"
    ];
    "astral-sh.uv" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.uv*" ];
    google-cloud-sdk = [
      "%ProgramFiles%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
      "%ProgramFiles(x86)%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
      "%LOCALAPPDATA%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
    ];
    chezmoi = [ "%LOCALAPPDATA%\\Programs\\chezmoi" ];
    direnv = [ "%LOCALAPPDATA%\\Programs\\direnv" ];
    "direnv.direnv" = [ "%LOCALAPPDATA%\\Programs\\direnv" ];
    dprint = [ "%LOCALAPPDATA%\\Programs\\dprint" ];
    "dprint.dprint" = [ "%LOCALAPPDATA%\\Programs\\dprint" ];
    fd = [ "%LOCALAPPDATA%\\Programs\\fd\\fd-v10.5.0-x86_64-pc-windows-msvc" ];
    "sharkdp.fd" = [ "%LOCALAPPDATA%\\Programs\\fd\\fd-v10.5.0-x86_64-pc-windows-msvc" ];
    "eza-community.eza" = [ "%LOCALAPPDATA%\\Programs\\eza" ];
    poppler-utils = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\oschwartz10612.Poppler*\\*\\Library\\bin"
    ];
    rustup = [ "%USERPROFILE%\\.cargo\\bin" ];
  };

  # Portable winget packages whose package exe name does not match the command name.
  wingetPortableLinksById = { };

}
