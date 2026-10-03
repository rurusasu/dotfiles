{ inputs, pkgs }:
let
  testPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = testPkgs;
    modules = [
      ../../modules/nvim
      {
        home = {
          username = "test-user";
          homeDirectory = "/tmp/neovim-test-home";
          stateVersion = "26.05";
        };
      }
    ];
  };
in
{
  package = home.config.programs.neovim.finalPackage;
  plugins = home.config.xdg.dataFile."nvim/site/pack/hm".source;
  lua = home.config.xdg.configFile."nvim/lua".source;
  init = pkgs.writeText "neovim-init.lua" home.config.programs.neovim.initLua;
}
