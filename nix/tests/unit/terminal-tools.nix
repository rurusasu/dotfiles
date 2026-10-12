{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
  inherit ((import ../fixtures/packages.nix { inherit inputs; })) mkPkgs;
  mkHome =
    system:
    let
      pkgs = mkPkgs system;
    in
    import "${inputs.home-manager}/lib/eval-config.nix" {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../home/common.nix
        ../../modules/editors/nvim
        {
          home = {
            username = "test-user";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            stateVersion = "26.05";
          };
        }
      ];
    };
in
{
  testTerminalToolsUseNativeHomeManagerModules = {
    expr = map (
      system:
      let
        home = mkHome system;
        cfg = home.config;
        count = pname: builtins.length (builtins.filter (p: (p.pname or "") == pname) cfg.home.packages);
      in
      {
        inherit system;
        lazygit = cfg.programs.lazygit.enable && count "lazygit" == 1;
        herdr = cfg.programs.herdr.enable && count "herdr" == 1;
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
      herdrConfig = builtins.fromTOML (
        builtins.readFile ../../../chezmoi/AppData/Roaming/herdr/config.toml
      );
    }) systems;
  };
}
