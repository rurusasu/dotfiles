{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes;
in
{
  testNeovimSettingsAndRuntimeDependenciesAcrossHomes = {
    expr = map (
      home:
      let
        cfg = home.config.programs.neovim;
      in
      {
        enabled = cfg.enable;
        initText = home.config.xdg.configFile."nvim/init.lua".text or null;
        writesInit = home.config.xdg.configFile."nvim/init.lua".enable or false;
        pluginData = home.config.xdg.dataFile."nvim/site/pack/hm".enable;
        internalPackages = cfg.extraPackages == [ ];
        serverDependencies =
          builtins.all
            (package: builtins.any (extra: extra.drvPath == package.drvPath) home.config.home.packages)
            [
              home.pkgs.gopls
              home.pkgs.ruff
              home.pkgs.ty
              home.pkgs.lua-language-server
              (home.pkgs.callPackage ../../../modules/typescript-language-server/package.nix { })
              home.pkgs.nixfmt
            ];
        remoteInstalled = builtins.any (
          package: package.drvPath == home.pkgs.neovim-remote.drvPath
        ) home.config.home.packages;
        globalServerPackages = builtins.any (
          package:
          builtins.elem package.drvPath (
            map (server: server.drvPath) [
              home.pkgs.nixd
              home.pkgs.gopls
              home.pkgs.ruff
            ]
          )
        ) home.config.home.packages;
      }
    ) homes;
    expected = map (
      home:
      let
        cfg = home.config.programs.neovim;
      in
      {
        enabled = true;
        initText = if cfg.initLua == "" then null else cfg.initLua;
        writesInit = cfg.initLua != "" && !cfg.sideloadInitLua;
        pluginData = cfg.plugins != [ ];
        internalPackages = true;
        serverDependencies = true;
        remoteInstalled = true;
        globalServerPackages = true;
      }
    ) homes;
  };
}
