{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  darwin = fixtures.mkHome "aarch64-darwin" [ ../../home/darwin.nix ];
  wsl = fixtures.mkHome "x86_64-linux" [ ../../home/wsl.nix ];
  packages = (import ../../modules/ai_agents/chatgpt).packages {
    pkgs = fixtures.mkPkgs "aarch64-darwin";
  };
in
{
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
            ((import ../../modules/ai_agents/chatgpt).packages {
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
