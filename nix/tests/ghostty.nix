{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  check =
    system:
    let
      pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs system;
      sets = import ../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      darwin = pkgs.stdenv.hostPlatform.isDarwin;
      package = if darwin then pkgs.ghostty-bin else pkgs.ghostty;
    in
    {
      selected = builtins.elem package sets.terminal;
      retainsWezterm = builtins.elem pkgs.wezterm sets.terminal;
      systemGui =
        if darwin then builtins.elem package (sets.darwinSystemPackagesForInstallFeatures [ ]) else true;
      notDarwinHome =
        if darwin then !(builtins.elem package (sets.darwinHomePackagesForInstallFeatures [ ])) else true;
      nixAttr = sets.supportReport.ghostty.${if darwin then "darwin" else "linux"}.nixAttr or null;
      windowsUnsupported = (sets.supportReport.ghostty.windows.unsupported or "") != "";
      providerErrors = builtins.filter (pkgs.lib.hasPrefix "ghostty:") sets.providerErrors;
    };
in
{
  testGhosttyPlatformSelection = {
    expr = builtins.map check systems;
    expected =
      builtins.map
        (nixAttr: {
          selected = true;
          retainsWezterm = true;
          systemGui = true;
          notDarwinHome = true;
          inherit nixAttr;
          windowsUnsupported = true;
          providerErrors = [ ];
        })
        [
          "ghostty-bin"
          "ghostty"
          "ghostty"
        ];
  };
}
