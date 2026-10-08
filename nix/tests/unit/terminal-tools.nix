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
      modules = [
        ../../modules/lazygit
        ../../modules/herdr
        {
          home = {
            username = "test-user";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            stateVersion = "26.05";
          };
          programs.bash.enable = true;
          programs.zsh.enable = true;
        }
      ];
    };
  pkgs = mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
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
  testLazygitKeepsWindowsWingetDistribution = {
    expr = {
      selected = builtins.elem "JesseDuffield.lazygit" sets.windowsOnly.winget;
      provider = sets.supportReport."JesseDuffield.lazygit".windows.provider;
      verifier = sets.wingetVerifyById."JesseDuffield.lazygit";
    };
    expected = {
      selected = true;
      provider = "winget";
      verifier = {
        command = "lazygit";
        args = [ "--version" ];
      };
    };
  };
}
