{
  fixtures,
}:
let
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
            programs = {
              ghostty.enable = true;
              zsh.enable = true;
              bash.enable = true;
            };
            xdg.configHome =
              if pkgs.stdenv.hostPlatform.isDarwin then
                "/Users/test-user/custom config"
              else
                "/home/test-user/custom config";
          }
        ];
      in
      {
        zshIntegration =
          home.config.programs.ghostty.enableZshIntegration
          && pkgs.lib.hasInfix "shell-integration/zsh/ghostty-integration" home.config.programs.zsh.initContent;
        bashIntegration =
          home.config.programs.ghostty.enableBashIntegration
          && pkgs.lib.hasInfix "shell-integration/bash/ghostty.bash" home.config.programs.bash.initExtra;
        ghosttySystemd = home.config.programs.ghostty.systemd.enable;
        ghosttyService = home.config.xdg.configFile ? "systemd/user/app-com.mitchellh.ghostty.service";
        customTarget = home.config.xdg.configFile."ghostty/config".target;
      }
    ) systems;
    expected = map (system: {
      zshIntegration = true;
      bashIntegration = true;
      ghosttySystemd = system != "aarch64-darwin";
      ghosttyService = system != "aarch64-darwin";
      customTarget = "custom config/ghostty/config";
    }) systems;
  };
}
