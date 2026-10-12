{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  darwin = fixtures.darwin.config;
  windows = fixtures.windowsPackages;
in
{
  testDockerDesktopCaskIsRestrictedToDarwin = {
    expr = {
      cask = builtins.any (cask: cask.name == "docker-desktop") darwin.homebrew.casks;
      windowsDesktop = windows ? "Docker.DockerDesktop";
    };
    expected = {
      cask = true;
      windowsDesktop = false;
    };
  };
}
