{
  inputs,
  fixtures,
  code,
}:
let
  fontContract =
    {
      system,
      modules,
    }:
    let
      home = fixtures.mkHome system modules;
      inherit (home) pkgs;
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
  testDisabledFontsDoNotConfigureDesktopOrInstallPackages = {
    expr =
      let
        home = fixtures.mkHome "x86_64-linux" [ ];
      in
      {
        fontconfig = home.config.fonts.fontconfig.enable;
        gtk = home.config.gtk.enable;
        managedFonts = builtins.any (
          package:
          builtins.elem (package.pname or "") [
            "udev-gothic-nf"
            "noto-fonts-color-emoji"
          ]
        ) home.config.home.packages;
      };
    expected = {
      fontconfig = false;
      gtk = false;
      managedFonts = false;
    };
  };

  testNixOSConfiguresManagedDefaultFonts = {
    expr =
      let
        system = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            platform = "linux";
          };
          modules = [
            (code.nix.defaults inputs).systemDefaults
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
    modules = [ (fixtures.homeModule "linux") ];
  };
  testWSLInstallsManagedFont = fontContract {
    system = "x86_64-linux";
    modules = [ (fixtures.homeModule "wsl") ];
  };
  testStandaloneDarwinHomeProfileInstallsManagedFont = fontContract {
    system = "aarch64-darwin";
    modules = [ (fixtures.homeModule "darwin") ];
  };

}
