# Packages distributed exclusively through the Windows installation adapters.
{ providerSource }:
let
  onepassword = import ../../modules/1password/windows-install.nix;
  git = import ../../modules/git/windows-install.nix;
  discord = import ../../modules/discord/windows-install.nix;
  lazygit = import ../../modules/lazygit/windows-install.nix;
  starship = import ../../modules/starship/windows-install.nix;
  chatgpt = import ../../modules/ai_agents/chatgpt/windows-install.nix;
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

  windowsOnlySupport =
    onepassword.windowsOnlySupport
    // git.windowsOnlySupport
    // discord.windowsOnlySupport
    // starship.windowsOnlySupport
    // lazygit.windowsOnlySupport
    // chatgpt.windowsOnlySupport
    // {
      "StablyAI.Orca" =
        mkWindowsOnlySupport "winget" "StablyAI.Orca"
          "macOS and Linux installations are owned by the Orca Home Manager module";
      "BurntSushi.ripgrep.MSVC" =
        mkWindowsOnlySupport "winget" "BurntSushi.ripgrep.MSVC"
          "Unix installation is owned by the ripgrep Home Manager module";
      "ajeetdsouza.zoxide" =
        mkWindowsOnlySupport "winget" "ajeetdsouza.zoxide"
          "Unix installation is owned by the zoxide Home Manager module";
      "junegunn.fzf" =
        mkWindowsOnlySupport "winget" "junegunn.fzf"
          "Unix installation is owned by the fzf Home Manager module";
      "eza-community.eza" =
        mkWindowsOnlySupport "winget" "eza-community.eza"
          "Unix installation is owned by the eza Home Manager module";
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
    };

in
{
  inherit windowsOnlySupport;
  # Windows adapter packages without a shared catalog entry.
  windowsOnly = {
    winget =
      onepassword.windowsOnly
      ++ git.windowsOnly
      ++ discord.windowsOnly
      ++ starship.windowsOnly
      ++ lazygit.windowsOnly
      ++ [
        "StablyAI.Orca"
        "BurntSushi.ripgrep.MSVC"
        "ajeetdsouza.zoxide"
        "eza-community.eza"
        "junegunn.fzf"
        "Microsoft.PowerToys"
        "Microsoft.VCRedist.2015+.x64"
        "Microsoft.VisualStudio.2022.BuildTools"
        "Microsoft.WindowsTerminal"
        "Microsoft.WSL"
      ];
    inherit (chatgpt) msstore;
    npm = [
      "agent-browser@0.38.1"
    ];
    pnpm = [ ];
  };
}
