# Home Manager modules
# Import all shared option definitions for Home Manager
{ ... }:
{
  imports = [
    ./chezmoi
    ./fd
    ./fzf
    ./ssh
    ./terminals
    ./tmux
    ./nixvim
  ];
}
