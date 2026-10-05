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
            home = {
              username = "test-user";
              homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
              stateVersion = "25.05";
            };
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
          specialArgs = { inherit inputs; };
          modules = [
            inputs.home-manager.nixosModules.home-manager
            ../../modules/nixos
          ];
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
  testStandaloneDarwinHomeProfileInstallsManagedFont = fontContract "aarch64-darwin" [
    ../../home/darwin.nix
  ];

  testStandaloneDarwinUsesHomeManagerFontInstallation = {
    expr =
      let
        home = inputs.self.homeConfigurations.aarch64-darwin.config;
        fontCopy = home.home.file."Library/Fonts/.home-manager-fonts-version".onChange;
      in
      {
        customActivation = home.home.activation ? installDotfilesFonts;
        nativeFontCopy = inputs.nixpkgs.lib.hasInfix "/Library/Fonts/HomeManager" fontCopy;
        copiesRealFiles = inputs.nixpkgs.lib.hasInfix "rsync" fontCopy;
      };
    expected = {
      customActivation = false;
      nativeFontCopy = true;
      copiesRealFiles = true;
    };
  };
}
