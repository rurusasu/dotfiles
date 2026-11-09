{ fixtures }:
let
  darwin = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "darwin")
  ];
  wsl = fixtures.mkHome "x86_64-linux" [
    (fixtures.homeModule "wsl")
  ];
  disabled = fixtures.mkHome "aarch64-darwin" [ ];
  cliOnly = fixtures.mkHome "aarch64-darwin" [ { programs.codex.enable = true; } ];
  desktopOnly = fixtures.mkHome "aarch64-darwin" [ { programs.chatgpt.enable = true; } ];
  hasBundledCli =
    home:
    builtins.any (
      path: home.pkgs.lib.hasPrefix "${home.config.programs.chatgpt.package}/" path
    ) home.config.home.sessionPath;
in
{
  testChatGPTAndCodexAreInactiveUntilEnabled = {
    expr = {
      desktop = disabled.config.programs.chatgpt.enable;
      cli = disabled.config.programs.codex.enable;
      paths = disabled.config.home.sessionPath;
      packages = builtins.filter (
        package:
        builtins.elem (package.pname or package.name) [
          "chatgpt"
          "codex"
        ]
      ) disabled.config.home.packages;
    };
    expected = {
      desktop = false;
      cli = false;
      paths = [ ];
      packages = [ ];
    };
  };
  testChatGPTDesktopEnablesItsBundledCliAndCliCanBeSelectedAlone = {
    expr = {
      desktopEnablesCli = desktopOnly.config.programs.codex.enable;
      desktopPackage = builtins.elem desktopOnly.config.programs.chatgpt.package desktopOnly.config.home.packages;
      cliLeavesDesktopDisabled = !cliOnly.config.programs.chatgpt.enable;
      cliIncludesBundle = hasBundledCli cliOnly;
      standalonePackage = cliOnly.config.programs.codex.package;
    };
    expected = {
      desktopEnablesCli = true;
      desktopPackage = true;
      cliLeavesDesktopDisabled = true;
      cliIncludesBundle = true;
      standalonePackage = null;
    };
  };
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
  testWslUsesTheLinuxCodexBundleWithoutInstallingTheDesktopApp = {
    expr = {
      enabled = wsl.config.programs.codex.enable;
      package = wsl.config.programs.codex.package == null && hasBundledCli wsl;
      desktopPackages = builtins.filter (
        package: (package.pname or package.name) == "chatgpt"
      ) wsl.config.home.packages;
    };
    expected = {
      enabled = true;
      package = true;
      desktopPackages = [ ];
    };
  };
}
