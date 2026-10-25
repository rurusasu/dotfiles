{ inputs }:
let
  fontContract =
    {
      system,
      modules,
    }:
    let
      pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
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
    in
    {
      expr = {
        homePackages = builtins.any (
          package: package.drvPath == pkgs.udev-gothic-nf.drvPath
        ) home.config.home.packages;
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
        cjkSansPackage = false;
        cjkSerifPackage = false;
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
            (import ../../default.nix { }).hostModules.nixos
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
    modules = [ (import ../../default.nix { inherit inputs; }).homeModules.linux ];
  };
  testWSLInstallsManagedFont = fontContract {
    system = "x86_64-linux";
    modules = [ (import ../../default.nix { }).homeModules.wsl ];
  };
  testStandaloneDarwinHomeProfileInstallsManagedFont = fontContract {
    system = "aarch64-darwin";
    modules = [ (import ../../default.nix { }).homeModules.darwin ];
  };

}
