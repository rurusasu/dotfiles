{ fixtures, homeConfigurations }:
let
  inherit (homeConfigurations) darwin;
  disabled = darwin.extendModules {
    modules = [ { dotfiles.desktop.enable = darwin.pkgs.lib.mkForce false; } ];
  };
  copied = darwin.extendModules {
    modules = [
      {
        home.homeDirectory = darwin.pkgs.lib.mkForce "/Volumes/Home/alice";
        targets.darwin.copyApps = {
          enable = true;
          directory = "Applications/Managed Apps";
        };
        targets.darwin.linkApps.enable = false;
      }
    ];
  };
in
{
  testDarwinDesktopLaunchesCopiedApplications = {
    expr = with copied.config; {
      apps = map (
        app: app.tile-data.file-data._CFURLString
      ) targets.darwin.defaults."com.apple.dock".persistent-apps;
      shortcuts = darwin.pkgs.lib.getAttrs [
        "cmd-enter"
        "cmd-shift-enter"
        "cmd-shift-a"
        "cmd-shift-o"
        "cmd-shift-slash"
      ] programs.aerospace.settings.mode.main.binding;
      others = targets.darwin.defaults."com.apple.dock".persistent-others;
      recents = targets.darwin.defaults."com.apple.dock".show-recents;
      finder = targets.darwin.defaults."com.apple.finder".NewWindowTarget;
      darkMode = targets.darwin.defaults.NSGlobalDomain.AppleInterfaceStyle;
    };
    expected = {
      apps = [
        "/System/Applications/Apps.app"
        "/Volumes/Home/alice/Applications/Managed Apps/ChatGPT.app"
        "/Volumes/Home/alice/Applications/Managed Apps/Dia.app"
        "/Volumes/Home/alice/Applications/Managed Apps/Ghostty.app"
        "/Volumes/Home/alice/Applications/Managed Apps/Obsidian.app"
      ];
      shortcuts = {
        cmd-enter = "exec-and-forget /usr/bin/open -na '/Volumes/Home/alice/Applications/Managed Apps/Ghostty.app'";
        cmd-shift-enter = "exec-and-forget /usr/bin/open -a '/Volumes/Home/alice/Applications/Managed Apps/Dia.app'";
        cmd-shift-a = "exec-and-forget /usr/bin/open -a '/Volumes/Home/alice/Applications/Managed Apps/ChatGPT.app'";
        cmd-shift-o = "exec-and-forget /usr/bin/open -a '/Volumes/Home/alice/Applications/Managed Apps/Obsidian.app'";
        cmd-shift-slash = "exec-and-forget /usr/bin/open -a /Applications/1Password.app";
      };
      others = [ ];
      recents = false;
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
