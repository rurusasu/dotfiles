{
  fixtures,
  code,
}:
let
  appearance = code.nix.modules.terminals.appearance;
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
in
{
  testAlacrittyUsesSharedAppearanceAndTerminalBindings = {
    expr = map (
      system:
      let
        pkgs = fixtures.mkPkgs system;
        home = fixtures.mkHome system [
          {
            programs.alacritty.enable = true;
            xdg.configHome =
              if pkgs.stdenv.hostPlatform.isDarwin then
                "/Users/test-user/custom config"
              else
                "/home/test-user/custom config";
          }
        ];
        cfg = home.config.programs.alacritty;
        bindings = cfg.settings.keyboard.bindings;
        themeImport = builtins.head (cfg.settings.general.import or [ ]);
      in
      {
        inherit system;
        enabled = cfg.enable;
        package = cfg.package == pkgs.alacritty;
        font = cfg.settings.font;
        theme = cfg.theme;
        themeImport = pkgs.lib.hasSuffix "/share/alacritty-theme/${appearance.theme}.toml" (
          toString themeImport
        );
        optionAsAlt = cfg.settings.window.option_as_alt or null;
        shiftEnter = builtins.any (
          binding: binding.key == "Return" && binding.mods == "Shift" && binding.chars == "\n"
        ) bindings;
        fontSizeKeys = builtins.all (binding: builtins.elem binding bindings) [
          {
            key = "0";
            mods = "Control | Shift";
            action = "ResetFontSize";
          }
          {
            key = "+";
            mods = "Control | Shift";
            action = "IncreaseFontSize";
          }
          {
            key = "-";
            mods = "Control | Shift";
            action = "DecreaseFontSize";
          }
        ];
        terminfoInstalled = builtins.any (
          package: package == cfg.package.terminfo
        ) home.config.home.packages;
        target = home.config.xdg.configFile."alacritty/alacritty.toml".target;
      }
    ) systems;
    expected = map (system: {
      inherit system;
      enabled = true;
      package = true;
      font = {
        inherit (appearance) font_size;
        normal.family = appearance.font_family;
      };
      inherit (appearance) theme;
      themeImport = true;
      optionAsAlt = if system == "aarch64-darwin" then "Both" else null;
      shiftEnter = true;
      fontSizeKeys = true;
      terminfoInstalled = true;
      target = "custom config/alacritty/alacritty.toml";
    }) systems;
  };
}
