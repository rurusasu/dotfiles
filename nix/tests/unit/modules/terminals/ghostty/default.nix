{
  fixtures,
  code,
  files,
}:
let
  appearance = code.nix.modules.terminals.appearance;
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
        pkgs = fixtures.mkPkgs system;
        home = fixtures.mkHome system [
          {
            programs.ghostty.enable = true;
            programs.wezterm.enable = true;
            programs.zsh.enable = true;
            programs.bash.enable = true;
            xdg.configHome =
              if pkgs.stdenv.hostPlatform.isDarwin then
                "/Users/test-user/custom config"
              else
                "/home/test-user/custom config";
          }
        ];
      in
      {
        ghosttyConfig =
          home.config.programs.ghostty.enable
          &&
            home.config.programs.ghostty.settings == (
              ghosttyBase
              // {
                keybind = code.nix.modules.terminals.ghostty.ghostty-renderer {
                  inherit (pkgs) lib;
                  bindings = (code.nix.home.keybindings.bindings { inherit (pkgs) lib; }).ghostty;
                  asList = true;
                };
              }
            );
        weztermConfig =
          home.config.programs.wezterm.enable
          && pkgs.lib.hasSuffix (builtins.readFile
            files.nix.modules.terminals.wezterm."wezterm.lua"
          ) home.config.programs.wezterm.extraConfig
          && home.config.programs.wezterm.settings.font_size == appearance.font_size
          && home.config.programs.wezterm.settings.color_scheme == appearance.theme;
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
        windowsWinget = fixtures.windowsPackages."wez.wezterm".PackageIdentifier;
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
      (fixtures.mkHome "x86_64-linux" [
        {
          programs.ghostty.enable = true;
          dotfiles.keybindings.fromWindowsExport = true;
          xdg.configHome = "/home/test-user/custom config";
        }
      ]).config.programs.ghostty.settings;
    expected = ghosttyBase // {
      config-file = [ "?/home/test-user/custom config/dotfiles/keybindings/ghostty.conf" ];
    };
  };
}
