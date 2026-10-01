{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  fontContract =
    system: modules:
    let
      pkgs = fixtures.mkPkgs system;
      sets = import ../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
      };
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          installFeatures = [ ];
        };
        modules = modules ++ [
          {
            home.username = "test-user";
            home.homeDirectory =
              if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            home.stateVersion = "25.05";
          }
        ];
      };
      containsFont = builtins.any (package: package.drvPath == pkgs.udev-gothic-nf.drvPath);
    in
    {
      expr = {
        fontBundle = containsFont sets.fonts;
        allPackages = containsFont sets.all;
        homePackages = containsFont home.config.home.packages;
      };
      expected = {
        fontBundle = true;
        allPackages = true;
        homePackages = true;
      };
    };
in
{
  testLinuxInstallsManagedFont = fontContract "x86_64-linux" [ ../../home/linux.nix ];
  testWSLInstallsManagedFont = fontContract "x86_64-linux" [ ../../home/wsl.nix ];
  testStandaloneDarwinHomeProfileInstallsManagedFont =
    let
      result = fontContract "aarch64-darwin" [
        ../../home/darwin.nix
        ../../home/standalone-darwin-fonts.nix
      ];
    in
    result
    // {
      expected = result.expected // {
        homePackages = true;
      };
    };
}
