{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  fontContract =
    {
      system,
      modules,
      japanese ? false,
    }:
    let
      pkgs = fixtures.mkPkgs system;
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
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
        homePackages = containsFont home.config.home.packages;
        emojiPackage = builtins.any (
          package: package.drvPath == pkgs.noto-fonts-color-emoji.drvPath
        ) home.config.home.packages;
        cjkSansPackage = builtins.any (
          package: package.drvPath == pkgs.noto-fonts-cjk-sans.drvPath
        ) home.config.home.packages;
        cjkSerifPackage = builtins.any (
          package: package.drvPath == pkgs.noto-fonts-cjk-serif.drvPath
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
        homePackages = true;
        emojiPackage = true;
        cjkSansPackage = japanese;
        cjkSerifPackage = japanese;
        fontconfig = true;
        defaultFonts = {
          monospace = [ "UDEV Gothic NF" ];
          sansSerif = [ "UDEV Gothic NF" ] ++ pkgs.lib.optional japanese "Noto Sans CJK JP";
          serif = [ "UDEV Gothic NF" ] ++ pkgs.lib.optional japanese "Noto Serif CJK JP";
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
            ../../hosts/shared/nixos/platform.nix
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

  testLinuxInstallsManagedFont = fontContract {
    system = "x86_64-linux";
    modules = [ ../../hosts/shared/linux-home.nix ];
  };
  testWSLInstallsManagedFont = fontContract {
    system = "x86_64-linux";
    modules = [ ../../hosts/x86_64-linux/wsl/home.nix ];
    japanese = true;
  };
  testStandaloneDarwinHomeProfileInstallsManagedFont = fontContract {
    system = "aarch64-darwin";
    modules = [ ../../hosts/aarch64-darwin/home.nix ];
  };

}
