{ inputs }:
let
  fixtures = import ../../../../fixtures/packages.nix { inherit inputs; };
  darwin = fixtures.mkHome "aarch64-darwin" [
    (fixtures.homeModule "darwin")
  ];
  wsl = fixtures.mkHome "x86_64-linux" [
    (fixtures.homeModule "wsl")
  ];
  disabled = fixtures.mkHome "aarch64-darwin" [ ];
  cliOnly = fixtures.mkHome "aarch64-darwin" [ { programs.codex.enable = true; } ];
  desktopOnly = fixtures.mkHome "aarch64-darwin" [ { programs.chatgpt.enable = true; } ];
  packages = (import ../../../../../modules/ai_agents/chatgpt/package.nix) {
    pkgs = fixtures.mkPkgs "aarch64-darwin";
  };
in
{
  testChatGPTAndCodexAreInactiveUntilEnabled = {
    expr = {
      desktop = disabled.config.programs.chatgpt.enable;
      cli = disabled.config.programs.codex.enable;
      migration = disabled.config.home.activation ? codexPruneManagedAgents;
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
      migration = false;
      packages = [ ];
    };
  };
  testChatGPTDesktopEnablesItsBundledCliAndCliCanBeSelectedAlone = {
    expr = {
      desktopEnablesCli = desktopOnly.config.programs.codex.enable;
      desktopPackage = builtins.elem desktopOnly.config.programs.chatgpt.package desktopOnly.config.home.packages;
      cliLeavesDesktopDisabled = !cliOnly.config.programs.chatgpt.enable;
      cliIncludesBundle = builtins.elem packages.codex cliOnly.config.home.packages;
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
      package =
        darwin.config.programs.codex.package == null
        && builtins.elem packages.codex darwin.config.home.packages;
      app = builtins.elem packages.chatgpt darwin.config.home.packages;
      cleanup = darwin.config.systemd.user.tmpfiles.rules;
    };
    expected = {
      managed = true;
      package = true;
      app = true;
      cleanup = [ ];
    };
  };
  testWslUsesTheLinuxCodexBundleWithoutInstallingTheDesktopApp = {
    expr = {
      enabled = wsl.config.programs.codex.enable;
      package =
        wsl.config.programs.codex.package == null
        &&
          builtins.elem
            ((import ../../../../../modules/ai_agents/chatgpt/package.nix) {
              pkgs = fixtures.mkPkgs "x86_64-linux";
            }).codex
            wsl.config.home.packages;
      cleanup = wsl.config.systemd.user.tmpfiles.rules;
      desktopPackages = builtins.filter (
        package: (package.pname or package.name) == "chatgpt"
      ) wsl.config.home.packages;
    };
    expected = {
      enabled = true;
      package = true;
      cleanup = [ ];
      desktopPackages = [ ];
    };
  };
}
