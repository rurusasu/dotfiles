{ inputs }:
let
  selected =
    packages:
    map (package: package.pname) (
      builtins.filter (package: (package.pname or "") == "comfyui") packages
    );
  homePackages =
    system: scope:
    ((import ../../fixtures/packages.nix { inherit inputs; }).mkHome system [ scope ])
    .config.home.packages;
in
{
  testComfyIsInstalledAcrossUnixHomes = {
    expr = {
      native = selected (
        homePackages "x86_64-linux" (
          (import ../../fixtures/packages.nix { inherit inputs; }).homeModule "linux"
        )
      );
      wsl = selected (
        homePackages "x86_64-linux" (
          (import ../../fixtures/packages.nix { inherit inputs; }).homeModule "wsl"
        )
      );
      darwin = selected (
        homePackages "aarch64-darwin" (
          (import ../../fixtures/packages.nix { inherit inputs; }).homeModule "darwin"
        )
      );
    };
    expected = {
      native = [ "comfyui" ];
      wsl = [ "comfyui" ];
      darwin = [ "comfyui" ];
    };
  };
  testComfyIsInstalledForArmLinux = {
    expr = selected (
      homePackages "aarch64-linux" (
        (import ../../fixtures/packages.nix { inherit inputs; }).homeModule "common"
      )
    );
    expected = [ "comfyui" ];
  };
}
