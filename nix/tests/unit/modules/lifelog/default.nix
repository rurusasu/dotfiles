{ fixtures }:
let
  pkgs = fixtures.mkPkgs "x86_64-linux";
  home = fixtures.mkHome "x86_64-linux" [
    {
      programs.git = {
        enable = true;
        settings.user.name = pkgs.lib.mkForce "work-user";
      };
      programs.lifelog = {
        enable = true;
        package = pkgs.hello;
      };
    }
  ];
in
{
  testLifelogUsesSelectedPackageAndGitUserCheckout = {
    expr = {
      installed = builtins.elem pkgs.hello home.config.home.packages;
      desktop = home.config.xdg.desktopEntries.lifelog.exec;
      checkout = home.config.programs.lifelog.sourceDirectory;
    };
    expected = {
      installed = true;
      desktop = "${pkgs.hello}/bin/lifelog";
      checkout = "/home/test-user/ghq/github.com/work-user/lifelog-core";
    };
  };
}
