{ fixtures }:
let
  native = fixtures.mkHome "x86_64-linux" [
    {
      i18n.inputMethod = {
        enable = true;
        fcitx5.waylandFrontend = true;
      };
    }
  ];
  wsl = fixtures.mkHome "x86_64-linux" [
    {
      i18n.inputMethod = {
        enable = true;
        fcitx5.wslIntegration.enable = true;
      };
    }
  ];
  serviceDisabled = wsl.extendModules {
    modules = [ { i18n.inputMethod.fcitx5.systemd.enable = false; } ];
  };
  startup =
    home:
    let
      service = home.config.systemd.user.services.fcitx5-daemon;
    in
    {
      command = service.Service.ExecStart;
      environment = service.Service.Environment or [ ];
      targets = service.Install.WantedBy;
      autostartOverrides = builtins.length home.config.xdg.autostart.entries;
      waylandFrontend = home.config.i18n.inputMethod.fcitx5.waylandFrontend;
    };
in
{
  testNativeFcitxUsesTheSessionEnvironment = {
    expr = startup native;
    expected = {
      command = [ "${native.config.i18n.inputMethod.package}/bin/fcitx5" ];
      environment = [ ];
      targets = [ "graphical-session.target" ];
      autostartOverrides = 0;
      waylandFrontend = true;
    };
  };

  testWslFcitxUsesItsExplicitDisplayIntegration = {
    expr = startup wsl;
    expected = {
      command = [ "${wsl.config.i18n.inputMethod.package}/bin/fcitx5 --disable=wayland" ];
      environment = [
        "DISPLAY=:0"
        "WAYLAND_DISPLAY="
      ];
      targets = [ "default.target" ];
      autostartOverrides = 1;
      waylandFrontend = false;
    };
  };

  testDisablingFcitxServiceRestoresAutostartOwnership = {
    expr = {
      service = serviceDisabled.config.systemd.user.services ? fcitx5-daemon;
      autostartOverrides = serviceDisabled.config.xdg.autostart.entries;
    };
    expected = {
      service = false;
      autostartOverrides = [ ];
    };
  };
}
