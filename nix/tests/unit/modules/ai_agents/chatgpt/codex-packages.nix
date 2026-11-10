{ fixtures }:
let
  darwin = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "darwin")
  ];
  hasBundledCli =
    home:
    builtins.any (
      path: home.pkgs.lib.hasPrefix "${home.config.programs.chatgpt.package}/" path
    ) home.config.home.sessionPath;
in
{
  testDarwinCodexUsesTheAppBundleThroughHomeManager = {
    expr = {
      managed = darwin.config.programs.codex.enable;
      package = darwin.config.programs.codex.package == null && hasBundledCli darwin;
      app = builtins.elem darwin.config.programs.chatgpt.package darwin.config.home.packages;
    };
    expected = {
      managed = true;
      package = true;
      app = true;
    };
  };
}
