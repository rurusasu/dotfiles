# Each package is owned by exactly one category module.
{
  pkgs,
  lib,
  context,
}:
let
  args = context // {
    inherit pkgs lib;
  };
  categories = {
    core = import ./core.nix args;
    desktop = import ./desktop.nix args;
    dev = import ./dev.nix args;
    editors = import ./editors.nix args;
    fonts = import ./fonts.nix args;
    infra = import ./infra.nix args;
    k8s = import ./k8s.nix args;
    llm = import ./llm.nix args;
    lsp = import ./lsp.nix args;
    native-desktop = import ./native-desktop.nix args;
    system = import ./system.nix args;
    terminal = import ./terminal.nix args;
  };
in
(import ./merge.nix { inherit lib; }) categories
