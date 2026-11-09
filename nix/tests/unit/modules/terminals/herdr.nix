{ fixtures }:
let
  home = fixtures.mkHome "aarch64-darwin" [
    {
      programs.herdr.enable = true;
      programs.zsh = {
        enable = true;
        package = null;
      };
    }
  ];
in
{
  testHerdrShellWithoutManagedZshPackage = {
    expr = home.config.programs.herdr.settings.terminal.default_shell;
    expected = home.pkgs.lib.getExe home.pkgs.bashInteractive;
  };
}
