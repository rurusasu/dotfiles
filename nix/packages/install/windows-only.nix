# Packages distributed exclusively through the Windows installation adapters.
{ providerSource }:
let
  mkWindowsOnlySupport = provider: identity: reason: {
    windows = {
      inherit provider identity;
      source = providerSource provider;
    };
    darwin = {
      unsupported = reason;
    };
    linux = {
      unsupported = reason;
    };
  };

  windowsOnlySupport = {
    "ajeetdsouza.zoxide" =
      mkWindowsOnlySupport "winget" "ajeetdsouza.zoxide"
        "Unix installation is owned by the zoxide Home Manager module";
    "junegunn.fzf" =
      mkWindowsOnlySupport "winget" "junegunn.fzf"
        "Unix installation is owned by the fzf Home Manager module";
    "Microsoft.PowerToys" =
      mkWindowsOnlySupport "winget" "Microsoft.PowerToys"
        "Windows system utility";
    "Microsoft.VCRedist.2015+.x64" =
      mkWindowsOnlySupport "winget" "Microsoft.VCRedist.2015+.x64"
        "Windows runtime component";
    "Microsoft.VisualStudio.2022.BuildTools" =
      mkWindowsOnlySupport "winget" "Microsoft.VisualStudio.2022.BuildTools"
        "Windows compiler toolchain";
    "Microsoft.WindowsTerminal" =
      mkWindowsOnlySupport "winget" "Microsoft.WindowsTerminal"
        "Windows shell host";
    "Microsoft.WSL" = mkWindowsOnlySupport "winget" "Microsoft.WSL" "Windows subsystem component";
    "9PLM9XGG6VKS" = mkWindowsOnlySupport "msstore" "9PLM9XGG6VKS" "Windows Store desktop application";
  };

in
{
  inherit windowsOnlySupport;
  # Windows adapter packages without a shared catalog entry.
  windowsOnly = {
    winget = [
      "ajeetdsouza.zoxide"
      "junegunn.fzf"
      "Microsoft.PowerToys"
      "Microsoft.VCRedist.2015+.x64"
      "Microsoft.VisualStudio.2022.BuildTools"
      "Microsoft.WindowsTerminal"
      "Microsoft.WSL"
    ];
    msstore = [
      "9PLM9XGG6VKS"
    ];
    npm = [
      "agent-browser@0.38.1"
    ];
    pnpm = [
      "@google/gemini-cli"
    ];
  };
}
