{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  darwinPkgs = fixtures.mkPkgs "aarch64-darwin";
  wslPkgs = fixtures.mkPkgs "x86_64-linux";
  darwin = fixtures.mkHome "aarch64-darwin" [ ../../hosts/aarch64-darwin/home.nix ];
  wsl = fixtures.mkHome "x86_64-linux" [ ../../hosts/x86_64-linux/wsl/home.nix ];
  packages = import ../../modules/ai_agents/chatgpt/packages.nix {
    inherit inputs;
    pkgs = darwinPkgs;
  };
  wslPackages = import ../../modules/ai_agents/chatgpt/packages.nix {
    inherit inputs;
    pkgs = wslPkgs;
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
  testWslUsesTheLinuxCodexBundleWithoutInstallingTheDesktopApp = {
    expr = {
      enabled = wsl.config.programs.codex.enable;
      package = wsl.config.programs.codex.package == wslPackages.codex;
      copies = builtins.length (
        builtins.filter (package: package == wslPackages.codex) wsl.config.home.packages
      );
      cleanup = wsl.config.systemd.user.tmpfiles.rules;
      desktopPackages = builtins.filter (
        package: (package.pname or package.name) == "chatgpt"
      ) wsl.config.home.packages;
    };
    expected = {
      enabled = true;
      package = true;
      copies = 1;
      cleanup = [ ];
      desktopPackages = [ ];
    };
  };
}
