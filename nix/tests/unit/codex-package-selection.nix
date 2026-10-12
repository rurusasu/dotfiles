{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  darwinPkgs = fixtures.mkPkgs "aarch64-darwin";
  darwin = fixtures.mkHome "aarch64-darwin" [ ../../hosts/aarch64-darwin/home.nix ];
  wsl = fixtures.mkHome "x86_64-linux" [ ../../hosts/x86_64-linux/wsl/home.nix ];
  packages = import ../../modules/ai_agents/chatgpt/packages.nix {
    inherit inputs;
    pkgs = darwinPkgs;
  };
in
{
  testDarwinCodexUsesTheAppBundleThroughHomeManager = {
    expr = {
      managed = darwin.config.programs.codex.enable;
      package = darwin.config.programs.codex.package == packages.codex;
      copies = builtins.length (
        builtins.filter (package: package == packages.codex) darwin.config.home.packages
      );
      app = builtins.elem packages.chatgpt darwin.config.home.packages;
      cleanup = darwin.config.systemd.user.tmpfiles.rules;
    };
    expected = {
      managed = true;
      package = true;
      copies = 1;
      app = true;
      cleanup = [ ];
    };
  };
  testWslCodexRetainsTheWindowsAppBoundary = {
    expr = {
      package = wsl.config.programs.codex.package;
      cleanup = wsl.config.systemd.user.tmpfiles.rules;
      desktopPackages = builtins.filter (
        package:
        builtins.elem (package.pname or package.name) [
          "chatgpt"
          "codex"
        ]
      ) wsl.config.home.packages;
    };
    expected = {
      package = null;
      cleanup = [ ];
      desktopPackages = [ ];
    };
  };
}
