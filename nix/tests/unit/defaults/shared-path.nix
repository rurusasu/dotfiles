{ fixtures }:
let
  home = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "common")
    ({ lib, ... }: {
      home.homeDirectory = lib.mkForce "/Users/shell-user";
      programs.bash.enable = lib.mkForce false;
    })
  ];
in
{
  testZshOnlyHomeKeepsSharedPaths = {
    expr = builtins.all (path: builtins.elem path home.config.home.sessionPath) [
      "/Users/shell-user/.bun/bin"
      "/Users/shell-user/.local/bin"
      "/Users/shell-user/bin"
      "/Users/shell-user/.local/npm/bin"
    ];
    expected = true;
  };
}
