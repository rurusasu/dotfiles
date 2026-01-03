# Terminal emulator configurations
# Options are defined in nix/modules/home/terminals/
{ ... }:
{
  imports = [
    ./wezterm
    ./windows-terminal
  ];

  # Enable WezTerm by default
  myHomeSettings.wezterm.enable = true;
}
