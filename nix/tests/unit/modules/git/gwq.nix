{ homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    ;
in
{
  testGwqSettingsGenerateEachHomesConfiguration = {
    expr = map (home: home.config.xdg.configFile."gwq/config.toml".source.drvPath) homes;
    expected = map (
      home:
      ((home.pkgs.formats.toml { }).generate "gwq-config.toml" home.config.dotfiles.gwq.settings).drvPath
    ) homes;
  };

  testWslGwqWorktreesUseAWindowsDrive = {
    expr =
      builtins.match "/mnt/[a-z]/.+" homeConfigurations.wsl.config.dotfiles.gwq.settings.worktree.basedir
      != null;
    expected = true;
  };
}
