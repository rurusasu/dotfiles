{ inputs }:
let
  appearance = import ../../modules/terminals/appearance.nix;
  ghosttyBase = {
    theme = [ appearance.theme ];
    font-family = [ appearance.font_family ];
    font-size = [ appearance.font_size ];
    macos-option-as-alt = [ true ];
  };
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

in
{
  testGhosttyPlatformSelection = {
    expr = map (
      system:
      let
        pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
        wezterm =
          (import ../../modules/terminals/wezterm {
            inherit pkgs;
            inherit (pkgs) lib;
            inherit (home) config;
          }).programs.wezterm;
        home = inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ../../modules/terminals/ghostty
            ../../modules/terminals/wezterm
            {
              home = {
                username = "test-user";
                homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
                stateVersion = "25.05";
              };
              programs.zsh.enable = true;
              programs.bash.enable = true;
              xdg.configHome =
                if pkgs.stdenv.hostPlatform.isDarwin then
                  "/Users/test-user/custom config"
                else
                  "/home/test-user/custom config";
            }
          ];
        };
      in
      {
        ghosttyConfig =
          home.config.programs.ghostty.enable
          &&
            home.config.programs.ghostty.settings == (
              ghosttyBase
              // {
                keybind = import ../../home/keybindings/ghostty-renderer.nix {
                  inherit (pkgs) lib;
                  bindings = (import ../../home/keybindings/bindings.nix { inherit (pkgs) lib; }).ghostty;
                  asList = true;
                };
              }
            );
        weztermConfig =
          home.config.programs.wezterm.enable
          && home.config.programs.wezterm.extraConfig == wezterm.extraConfig
          && home.config.programs.wezterm.settings.font_size == wezterm.settings.font_size
          && home.config.programs.wezterm.settings.color_scheme == wezterm.settings.color_scheme;
        zshIntegration =
          home.config.programs.ghostty.enableZshIntegration
          && pkgs.lib.hasInfix "shell-integration/zsh/ghostty-integration" home.config.programs.zsh.initContent
          && pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.zsh.initContent;
        bashIntegration =
          home.config.programs.ghostty.enableBashIntegration
          && pkgs.lib.hasInfix "shell-integration/bash/ghostty.bash" home.config.programs.bash.initExtra
          && pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.bash.initExtra;
        ghosttySystemd = home.config.programs.ghostty.systemd.enable;
        ghosttyService = home.config.xdg.configFile ? "systemd/user/app-com.mitchellh.ghostty.service";
        customTarget = home.config.xdg.configFile."ghostty/config".target;
        windowsWinget =
          (import ../fixtures/packages.nix { inherit inputs; })
          .windowsPackages."wez.wezterm".PackageIdentifier;
      }
    ) systems;
    expected = map (system: {
      ghosttyConfig = true;
      weztermConfig = true;
      zshIntegration = true;
      bashIntegration = true;
      ghosttySystemd = system != "aarch64-darwin";
      ghosttyService = system != "aarch64-darwin";
      customTarget = "custom config/ghostty/config";
      windowsWinget = "wez.wezterm";
    }) systems;
  };
  testWslGhosttyReadsChezmoiExportAtConfiguredXdgPath = {
    expr =
      (inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
        modules = [
          ../../modules/terminals/ghostty
          ../../home/keybindings/windows-export.nix
          {
            home = {
              username = "test-user";
              homeDirectory = "/home/test-user";
              stateVersion = "25.05";
            };
            dotfiles.keybindings.fromWindowsExport = true;
            xdg.configHome = "/home/test-user/custom config";
          }
        ];
      }).config.programs.ghostty.settings;
    expected = ghosttyBase // {
      config-file = [ "?/home/test-user/custom config/dotfiles/keybindings/ghostty.conf" ];
    };
  };
}
