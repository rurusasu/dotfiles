{ inputs }:
let
  check =
    system:
    let
      pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
      ghostty = (import ../../modules/terminals/ghostty/defaults.nix { inherit pkgs; }).programs.ghostty;
      wezterm =
        (import ../../modules/terminals/wezterm/defaults.nix {
          inherit pkgs;
          lib = pkgs.lib;
        }).programs.wezterm;
      sets = import ../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
      };
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ../../modules/terminals/ghostty/defaults.nix
          ../../modules/terminals/wezterm/defaults.nix
          {
            home.username = "test-user";
            home.homeDirectory =
              if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            home.stateVersion = "25.05";
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
              ../../modules/darwin/ghostty.nix
            else
              ../../modules/nixos/ghostty.nix
          )
        ];
      };
      copies =
        package:
        builtins.length (builtins.filter (p: p.outPath == package.outPath) home.config.home.packages);
    in
    {
      catalogInstalls = builtins.any (
        p: p.drvPath == home.config.programs.ghostty.package.drvPath || p.drvPath == wezterm.package.drvPath
      ) sets.terminal;
      ghosttyHomeCopies = copies home.config.programs.ghostty.package;
      weztermHomeCopies = copies wezterm.package;
      ghosttyConfig =
        home.config.programs.ghostty.enable
        &&
          home.config.programs.ghostty.settings == builtins.mapAttrs (_: value: [ value ]) ghostty.settings;
      weztermConfig =
        home.config.programs.wezterm.enable
        && home.config.programs.wezterm.extraConfig == wezterm.extraConfig
        && home.config.programs.wezterm.settings.font_size == wezterm.settings.font_size
        && home.config.programs.wezterm.settings.color_scheme == wezterm.settings.color_scheme;
      zshIntegration =
        home.config.programs.ghostty.enableZshIntegration
        && home.config.programs.wezterm.enableZshIntegration
        && pkgs.lib.hasInfix "shell-integration/zsh/ghostty-integration" home.config.programs.zsh.initContent
        && pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.zsh.initContent;
      bashIntegration =
        home.config.programs.ghostty.enableBashIntegration
        && home.config.programs.wezterm.enableBashIntegration
        && pkgs.lib.hasInfix "shell-integration/bash/ghostty.bash" home.config.programs.bash.initExtra
        && pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.bash.initExtra;
      ghosttySystemd = home.config.programs.ghostty.systemd.enable;
      ghosttyService = home.config.xdg.configFile ? "systemd/user/app-com.mitchellh.ghostty.service";
      customTarget = home.config.xdg.configFile."ghostty/config".target;
      windowsWinget = sets.wingetMap.wezterm;
      providerErrors = builtins.filter (
        error: pkgs.lib.hasPrefix "ghostty:" error || pkgs.lib.hasPrefix "wezterm:" error
      ) sets.providerErrors;
    };
  expected = system: {
    catalogInstalls = false;
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
    providerErrors = [ ];
  };
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
in
{
  testGhosttyPlatformSelection = {
    expr = map check systems;
    expected = map expected systems;
  };
}
