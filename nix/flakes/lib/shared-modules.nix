{ inputs }:
let
  nixvimModule =
    if inputs.nixvim ? homeModules
    then inputs.nixvim.homeModules.nixvim
    else inputs.nixvim.homeManagerModules.nixvim;

  # Custom Home Manager modules
  homeModules = ../../../modules/home;
in
[
  nixvimModule
  homeModules
]
