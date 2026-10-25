{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
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
        sideloadInit = cfg.sideloadInitLua;
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
    expected = map (_: {
      enabled = sharedConfig.programs.neovim.enable;
      sideloadInit = false;
      writesInit = true;
      pluginData = true;
      internalPackages = true;
      serverDependencies = true;
      remoteInstalled = true;
      globalServerPackages = true;
    }) homes;
  };
}
