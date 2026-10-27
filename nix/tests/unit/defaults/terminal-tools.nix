{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
in
{
  testTerminalToolsUseNativeHomeManagerModules = {
    expr = map (
      system:
      let
        home =
          let
            pkgs = (import ../../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
          in
          import "${inputs.home-manager}/lib/eval-config.nix" {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [
              ((import ../../fixtures/packages.nix { inherit inputs; }).homeModule "common")
              { programs.neovim.enable = true; }
              {
                home = {
                  username = "test-user";
                  homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
                  stateVersion = "26.05";
                };
              }
            ];
          };
        cfg = home.config;
      in
      {
        inherit system;
        lazygit = cfg.programs.lazygit.enable;
        herdr = cfg.programs.herdr.enable;
        bashWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.bash.initExtra;
        zshWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.zsh.initContent;
        herdrConfig = cfg.programs.herdr.settings;
      }
    ) systems;
    expected = map (system: {
      inherit system;
      lazygit = true;
      herdr = true;
      bashWrapper = true;
      zshWrapper = true;
      herdrConfig = (import ../../../modules/herdr/default.nix { }).programs.herdr.settings;
    }) systems;
  };
}
