{
  windowsOnly = [ "JesseDuffield.lazygit" ];
  windowsOnlySupport."JesseDuffield.lazygit" = {
    windows = {
      provider = "winget";
      source = "winget";
      identity = "JesseDuffield.lazygit";
    };
    darwin.unsupported = "Unix installation is owned by the lazygit Home Manager module";
    linux.unsupported = "Unix installation is owned by the lazygit Home Manager module";
  };
  wingetVerifyById."JesseDuffield.lazygit" = {
    command = "lazygit";
    args = [ "--version" ];
  };
}
