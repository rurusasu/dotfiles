{ pkgs }:
let
  buildPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  customPackages = [
    {
      name = "neovim";
      path = buildPkgs.callPackage ../../packages/neovim { };
    }
  ]
  ++ buildPkgs.lib.optionals buildPkgs.stdenv.hostPlatform.isLinux [
    {
      name = "chatgpt";
      path = buildPkgs.callPackage ../../packages/chatgpt { };
    }
  ]
  ++ buildPkgs.lib.optionals buildPkgs.stdenv.hostPlatform.isDarwin [
    {
      name = "dia-browser";
      path = buildPkgs.callPackage ../../packages/dia-browser { };
    }
    {
      name = "hammerspoon";
      path = buildPkgs.callPackage ../../packages/hammerspoon { };
    }
    {
      name = "orca-editor";
      path = buildPkgs.callPackage ../../packages/orca-editor { };
    }
  ];
in
buildPkgs.linkFarm "custom-package-builds" customPackages
