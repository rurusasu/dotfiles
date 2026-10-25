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
      native = selected (homePackages "x86_64-linux" (import ../../hosts { inherit inputs; }).linuxHome);
      wsl = selected (homePackages "x86_64-linux" ../../home/wsl.nix);
      darwin = selected (homePackages "aarch64-darwin" ../../home/darwin.nix);
    };
    expected = {
      native = [ "comfyui" ];
      wsl = [ "comfyui" ];
      darwin = [ "comfyui" ];
    };
  };
  testComfyIsInstalledForArmLinux = {
    expr = selected (homePackages "aarch64-linux" ../../home/common.nix);
    expected = [ "comfyui" ];
  };
}
