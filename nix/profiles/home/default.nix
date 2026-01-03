# Home Manager profile
# Imports all home configurations and enables default programs
{ ... }:
{
  imports = [
    ../nixvim
    ./programs
  ];

  # Enable default programs via modules
  myHomeSettings = {
    nixvim.enable = true;
    tmux.enable = true;
  };

  home.stateVersion = "24.05";
}
