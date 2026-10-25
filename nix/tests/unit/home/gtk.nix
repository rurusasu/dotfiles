{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    mkHome
    common
    linux
    wsl
    darwin
    ;
  gtkReference = mkHome {
    system = "x86_64-linux";
    module = ../../../modules/fonts/gtk.nix;
  };
  gtk = gtkReference.config.gtk;
  fontName = "${gtk.font.name} ${toString gtk.font.size}";
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
        gtk3 = home.pkgs.lib.hasInfix "gtk-font-name=${fontName}" (
          home.config.xdg.configFile."gtk-3.0/settings.ini".text or ""
        );
        gtk4 = home.pkgs.lib.hasInfix "gtk-font-name=${fontName}" (
          home.config.xdg.configFile."gtk-4.0/settings.ini".text or ""
        );
        portalFont = home.config.dconf.settings."org/gnome/desktop/interface"."font-name" or null;
      }) desktopHomes;
      commonEnabled = common.config.gtk.enable;
      darwinEnabled = darwin.config.gtk.enable;
    };
    expected = {
      homes = map (_: {
        enabled = gtk.enable;
        gtk3 = true;
        gtk4 = true;
        portalFont = fontName;
      }) desktopHomes;
      commonEnabled = false;
      darwinEnabled = false;
    };
  };
}
