{ inputs, pkgs }:
let
  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import pkgs.path {
      system = pkgs.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../../home/common.nix
      ../../modules/editors/nvim
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
