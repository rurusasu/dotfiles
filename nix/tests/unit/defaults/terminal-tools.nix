{ fixtures }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
in
{
  testTerminalToolsUseNativeHomeManagerModules = {
    expr = map (
      system:
      let
        home = fixtures.mkHome system [ (fixtures.homeModule "common") ];
        cfg = home.config;
      in
      {
        inherit system;
        lazygit = cfg.programs.lazygit.enable;
        herdr = cfg.programs.herdr.enable;
        bashWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.bash.initExtra;
        zshWrapper = home.pkgs.lib.hasInfix "function lg()" cfg.programs.zsh.initContent;
        herdrConfig = {
          inherit (cfg.programs.herdr.settings) onboarding terminal;
          prefix = cfg.programs.herdr.settings.keys.prefix;
          managedFile = cfg.xdg.configFile."herdr/config.toml".force;
        };
      }
    ) systems;
    expected = map (system: {
      inherit system;
      lazygit = true;
      herdr = true;
      bashWrapper = true;
      zshWrapper = true;
      herdrConfig = {
        onboarding = false;
        terminal = {
          shell_mode = "auto";
          new_cwd = "follow";
        };
        prefix = "ctrl+space";
        managedFile = true;
      };
    }) systems;
  };
}
