{ inputs }:
let
  nixvimModule =
    if inputs.nixvim ? homeModules
    then inputs.nixvim.homeModules.nixvim
    else inputs.nixvim.homeManagerModules.nixvim;
in
[
  nixvimModule
  # Custom Home Manager modules (inline import to work with flake paths)
  ({ ... }: {
    imports = [
      ../../../modules/home/terminals
      ../../../modules/home/tmux
      ../../../modules/home/nixvim
    ];
  })
]
