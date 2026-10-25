{ inputs }:
let
  selected =
    packages:
    map (package: package.pname) (
      builtins.filter (package: (package.pname or "") == "comfyui") packages
    );
  homePackages =
    system: scope:
    ((import ../fixtures/packages.nix { inherit inputs; }).mkHome system [ scope ])
    .config.home.packages;
in
{
  testComfyIsInstalledAcrossUnixHomes = {
    expr = {
      native = selected (
        homePackages "x86_64-linux" (import ../../default.nix { inherit inputs; }).homeModules.linux
      );
      wsl = selected (homePackages "x86_64-linux" (import ../../default.nix { }).homeModules.wsl);
      darwin = selected (homePackages "aarch64-darwin" (import ../../default.nix { }).homeModules.darwin);
    };
    expected = {
      native = [ "comfyui" ];
      wsl = [ "comfyui" ];
      darwin = [ "comfyui" ];
    };
  };
  testComfyIsInstalledForArmLinux = {
    expr = selected (homePackages "aarch64-linux" (import ../../default.nix { }).homeModules.common);
    expected = [ "comfyui" ];
  };
}
