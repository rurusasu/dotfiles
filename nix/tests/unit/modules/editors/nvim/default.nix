{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testNeovimSettingsAndRuntimeDependenciesAcrossHomes = {
    expr = map (
      home:
      let
        cfg = home.config.programs.nixvim;
      in
      {
        enabled = cfg.enable;
        usesGlobalPackages = cfg.nixpkgs.useGlobalPackages;
        internalPackages = cfg.extraPackages == [ ] && cfg.extraPackagesAfter == [ ];
        serverDependencies =
          builtins.all
            (package: builtins.any (extra: extra.drvPath == package.drvPath) home.config.home.packages)
            [
              home.pkgs.gopls
              home.pkgs.ruff
              home.pkgs.ty
              home.pkgs.lua-language-server
              home.pkgs.nixfmt
              home.pkgs.csharp-ls
              home.pkgs.dotnet-sdk_10
            ];
        remoteInstalled = builtins.any (
          package: package.drvPath == home.pkgs.neovim-remote.drvPath
        ) home.config.home.packages;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      internalPackages = true;
      usesGlobalPackages = true;
      serverDependencies = true;
      remoteInstalled = true;
    }) homes;
  };
}
