{ inputs }:
let
  nixvimModule =
    if inputs.nixvim ? homeModules
    then inputs.nixvim.homeModules.nixvim
    else inputs.nixvim.homeManagerModules.nixvim;
in
[
  nixvimModule
]
