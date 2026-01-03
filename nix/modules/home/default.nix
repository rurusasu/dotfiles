# Home Manager modules
# Import all shared option definitions for Home Manager
{ ... }:
{
  imports = [
    ./terminals
    ./tmux
    ./nixvim
  ];
}
