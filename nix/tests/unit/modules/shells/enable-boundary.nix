{ fixtures }:
let
  aliases =
    enabled:
    let
      home = fixtures.mkHome "x86_64-linux" [
        {
          programs = {
            bash.enable = true;
            zsh.enable = true;
            ripgrep.enable = enabled;
            fd.enable = enabled;
          };
        }
      ];
    in
    {
      bashGrep = home.config.programs.bash.shellAliases.grep or null;
      bashFind = home.config.programs.bash.shellAliases.find or null;
      zshGrep = home.config.programs.zsh.shellAliases.grep or null;
    };
in
{
  testShellAliasesFollowEnabledTools = {
    expr = map aliases [
      false
      true
    ];
    expected = [
      {
        bashGrep = null;
        bashFind = null;
        zshGrep = null;
      }
      {
        bashGrep = "rg";
        bashFind = "fd";
        zshGrep = "rg";
      }
    ];
  };
}
