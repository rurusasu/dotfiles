{
  windowsOnly = [ "Starship.Starship" ];
  windowsOnlySupport."Starship.Starship" = {
    windows = {
      provider = "winget";
      source = "winget";
      identity = "Starship.Starship";
    };
    darwin.unsupported = "Unix installation is owned by the Starship Home Manager module";
    linux.unsupported = "Unix installation is owned by the Starship Home Manager module";
  };
  wingetVerifyById."Starship.Starship" = {
    command = "starship";
    args = [ "--version" ];
  };
}
