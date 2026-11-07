{ fixtures }:
let
  pkgs = fixtures.mkPkgs "x86_64-linux";
  home = fixtures.mkHome "x86_64-linux" [
    {
      programs.lifelog = {
        enable = true;
        package = pkgs.hello;
      };
    }
  ];
in
{
  testLifelogLaunchersUseSelectedPackage = {
    expr = {
      installed = builtins.elem pkgs.hello home.config.home.packages;
      command = toString home.config.home.file.".local/bin/lifelog".source;
      desktop = home.config.xdg.desktopEntries.lifelog.exec;
    };
    expected = {
      installed = true;
      command = "${pkgs.hello}/bin/lifelog";
      desktop = "${pkgs.hello}/bin/lifelog";
    };
  };
}
