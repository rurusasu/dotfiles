{ inputs }:
let
  nixvimModule =
    if inputs.nixvim ? homeModules
    then inputs.nixvim.homeModules.nixvim
    else inputs.nixvim.homeManagerModules.nixvim;
in
[
  nixvimModule
  # Custom Home Manager modules
  # Path is relative from this file: nix/flakes/lib/ -> nix/modules/home/
  ../../modules/home/fd
  ../../modules/home/fzf
  ../../modules/home/terminals
  ../../modules/home/tmux
  ../../modules/home/nixvim
]
