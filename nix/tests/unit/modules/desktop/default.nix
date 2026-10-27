{ fixtures }:
let
  darwin = fixtures.mkHome "aarch64-darwin" [ (fixtures.homeModule "darwin") ];
  disabled = darwin.extendModules {
    modules = [ { dotfiles.desktop.enable = darwin.pkgs.lib.mkForce false; } ];
  };
in
{
  testDarwinDesktopUsesConfiguredApplicationPackages = {
    expr = with darwin.config; {
      apps = map (
        app: app.tile-data.file-data._CFURLString
      ) targets.darwin.defaults."com.apple.dock".persistent-apps;
      finder = targets.darwin.defaults."com.apple.finder".NewWindowTarget;
      darkMode = targets.darwin.defaults.NSGlobalDomain.AppleInterfaceStyle;
    };
    expected = with darwin.config; {
      apps = [
        "${programs.chatgpt.package}/Applications/ChatGPT.app"
        "${programs.dia.package}/Applications/Dia.app"
        "${programs.ghostty.package}/Applications/Ghostty.app"
        "${darwin.pkgs.obsidian}/Applications/Obsidian.app"
      ];
      finder = "PfHm";
      darkMode = "Dark";
    };
  };

  testDisabledDesktopDoesNotInstallActivationScripts = {
    expr = {
      zoom = disabled.config.home.activation.globalZoomShortcut.data or "";
      refresh = disabled.config.home.activation.refreshDarwinSettings.data or "";
      dock = disabled.config.targets.darwin.defaults."com.apple.dock".persistent-apps;
      finder = disabled.config.targets.darwin.defaults."com.apple.finder".NewWindowTarget or null;
    };
    expected = {
      zoom = "";
      refresh = "";
      dock = null;
      finder = null;
    };
  };

  testDarwinDesktopIsInertOnLinuxEvenWhenEnabled = {
    expr =
      map
        (
          platform:
          let
            home = fixtures.mkHome "x86_64-linux" [
              (fixtures.homeModule platform)
              { dotfiles.desktop.enable = true; }
            ];
          in
          {
            zoom = home.config.home.activation.globalZoomShortcut.data or "";
            refresh = home.config.home.activation.refreshDarwinSettings.data or "";
            dock = home.config.targets.darwin.defaults."com.apple.dock".persistent-apps;
            finder = home.config.targets.darwin.defaults."com.apple.finder".NewWindowTarget or null;
          }
        )
        [
          "linux"
          "wsl"
        ];
    expected = builtins.genList (_: {
      zoom = "";
      refresh = "";
      dock = null;
      finder = null;
    }) 2;
  };
}
