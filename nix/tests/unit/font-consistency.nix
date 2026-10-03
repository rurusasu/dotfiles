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
        allPackages = containsFont sets.all;
        homePackages = containsFont home.config.home.packages;
        emojiPackage = builtins.any (
          package: package.drvPath == pkgs.noto-fonts-color-emoji.drvPath
        ) home.config.home.packages;
        fontconfig = home.config.fonts.fontconfig.enable;
        defaultFonts = {
          inherit (home.config.fonts.fontconfig.defaultFonts)
            monospace
            sansSerif
            serif
            emoji
            ;
        };
      };
      expected = {
        allPackages = false;
        homePackages = true;
        emojiPackage = true;
        fontconfig = true;
        defaultFonts = {
          monospace = [ "UDEV Gothic NF" ];
          sansSerif = [ "UDEV Gothic NF" ];
          serif = [ "UDEV Gothic NF" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
in
{
  testNixOSConfiguresManagedDefaultFonts = {
    expr =
      let
        system = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ../../modules/nixos ];
        };
      in
      {
        fontDir = system.config.fonts.fontDir.enable;
        fontconfig = system.config.fonts.fontconfig.enable;
        inherit (system.config.fonts.fontconfig.defaultFonts)
          monospace
          sansSerif
          serif
          emoji
          ;
      };
    expected = {
      fontDir = true;
      fontconfig = true;
      monospace = [ "UDEV Gothic NF" ];
      sansSerif = [ "UDEV Gothic NF" ];
      serif = [ "UDEV Gothic NF" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

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
