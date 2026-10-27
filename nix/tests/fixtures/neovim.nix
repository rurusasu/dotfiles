{ inputs, pkgs }:
let
  fixtures = import ./packages.nix { inherit inputs; };
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    (fixtures.homeModule "common")
    ({ lib, ... }: {
      home.homeDirectory = lib.mkForce "/tmp/neovim-test-home";
      home.stateVersion = lib.mkForce "26.05";
      programs.neovim.enable = true;
    })
  ];
in
{
  package = home.config.programs.neovim.finalPackage;
  plugins = home.config.xdg.dataFile."nvim/site/pack/hm".source;
  lua = pkgs.runCommand "neovim-config-lua" { } ''
    mkdir -p "$out"
    cp -r ${home.config.xdg.configFile."nvim/lua".source}/. "$out/"
    chmod -R u+w "$out"
    cp ${
      home.config.xdg.configFile."nvim/lua/config/shared_keybindings.lua".source
    } "$out/config/shared_keybindings.lua"
  '';
  init = pkgs.writeText "neovim-init.lua" home.config.programs.neovim.initLua;
}
