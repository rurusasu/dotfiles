{ inputs }:
let
  check =
    system:
    let
      pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
      wezterm =
        (import ../../modules/terminals/wezterm/defaults.nix {
          inherit pkgs;
          inherit (pkgs) lib;
          inherit (home) config;
        }).programs.wezterm;
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ../../modules/terminals/ghostty/defaults.nix
          ../../modules/terminals/wezterm/defaults.nix
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
        ]
        ++ [
          (
            if pkgs.stdenv.hostPlatform.isDarwin then
              ../../hosts/aarch64-darwin/ghostty.nix
            else
              ../../hosts/shared/linux-ghostty.nix
          )
        ];
      };
      copies =
        package:
        builtins.length (builtins.filter (p: p.outPath == package.outPath) home.config.home.packages);
    in
    {
      ghosttyHomeCopies = copies home.config.programs.ghostty.package;
      weztermHomeCopies = copies wezterm.package;
      ghosttyConfig =
        home.config.programs.ghostty.enable
        && home.config.programs.ghostty.settings == { }
        &&
          home.config.xdg.configFile."ghostty/config".text
          == builtins.readFile ../../modules/terminals/ghostty/config.ghostty
          + "\n"
          + (import ../../home/keybindings/bindings.nix { inherit (pkgs) lib; }).ghosttyConfig;
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
    };
  expected = system: {
    ghosttyHomeCopies = 1;
    weztermHomeCopies = 1;
    ghosttyConfig = true;
    weztermConfig = true;
    zshIntegration = true;
    bashIntegration = true;
    ghosttySystemd = system != "aarch64-darwin";
    ghosttyService = system != "aarch64-darwin";
    customTarget = "custom config/ghostty/config";
    windowsWinget = "wez.wezterm";
  };
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  exportedHome =
    let
      pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../../modules/terminals/ghostty/defaults.nix
        ../../hosts/shared/linux-ghostty.nix
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
    };
in
{
  testGhosttyPlatformSelection = {
    expr = map check systems;
    expected = map expected systems;
  };
  testWslGhosttyReadsChezmoiExportAtConfiguredXdgPath = {
    expr = exportedHome.config.xdg.configFile."ghostty/config".text;
    expected =
      builtins.readFile ../../modules/terminals/ghostty/config.ghostty
      + "\nconfig-file = ?/home/test-user/custom config/dotfiles/keybindings/ghostty.conf\n";
  };
}
