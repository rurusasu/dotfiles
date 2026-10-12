{
  pkgs,
  chatgptDesktopCheck ? null,
}:
let
  buildPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  customPackages = [
    {
      name = "orca-editor";
      path = buildPkgs.callPackage ../../modules/editors/orca/package.nix { };
    }
  ]
  ++ buildPkgs.lib.optionals (chatgptDesktopCheck != null) [
    {
      name = "chatgpt-desktop";
      path = chatgptDesktopCheck;
    }
  ]
  ++ buildPkgs.lib.optionals buildPkgs.stdenv.hostPlatform.isDarwin [
    {
      name = "dia-browser";
      path = buildPkgs.callPackage ../../modules/browsers/dia/package.nix { };
    }
  ];
in
buildPkgs.linkFarm "custom-package-builds" customPackages
