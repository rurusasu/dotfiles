{ ... }:
{
  imports = [
    ../nixvim
    ./programs
    ./bash
  ];

  home.stateVersion = "24.05";
}
