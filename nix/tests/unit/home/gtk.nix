{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    common
    linux
    wsl
    darwin
    ;
  fontName = home: "${home.config.gtk.font.name} ${toString home.config.gtk.font.size}";
  desktopHomes = [
    wsl
    linux
  ];
in
{
  testLinuxDesktopGtkAndPortalUseTheDeclaredFont = {
    expr = {
      homes = map (home: {
        enabled = home.config.gtk.enable;
        gtk3 =
          home.pkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "gtk-font-name=${fontName home}")
            (home.config.xdg.configFile."gtk-3.0/settings.ini".text or "");
        gtk4 =
          home.pkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "gtk-font-name=${fontName home}")
            (home.config.xdg.configFile."gtk-4.0/settings.ini".text or "");
        portalFont = home.config.dconf.settings."org/gnome/desktop/interface"."font-name" or null;
      }) desktopHomes;
      commonEnabled = common.config.gtk.enable;
      darwinEnabled = darwin.config.gtk.enable;
    };
    expected = {
      homes = map (home: {
        enabled = true;
        gtk3 = true;
        gtk4 = true;
        portalFont = fontName home;
      }) desktopHomes;
      commonEnabled = false;
      darwinEnabled = false;
    };
  };
}
