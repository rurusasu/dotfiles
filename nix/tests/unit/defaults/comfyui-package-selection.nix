{ fixtures }:
let
  selected =
    packages:
    map (package: package.pname) (
      builtins.filter (package: (package.pname or "") == "comfyui") packages
    );
  homePackages = system: scope: (fixtures.mkHome system [ scope ]).config.home.packages;
in
{
  testComfyIsInstalledAcrossUnixHomes = {
    expr = {
      native = selected (homePackages "x86_64-linux" (fixtures.homeModule "linux"));
      wsl = selected (homePackages "x86_64-linux" (fixtures.homeModule "wsl"));
      darwin = selected (homePackages "aarch64-darwin" (fixtures.homeModule "darwin"));
    };
    expected = {
      native = [ "comfyui" ];
      wsl = [ "comfyui" ];
      darwin = [ "comfyui" ];
    };
  };
  testComfyIsInstalledForArmLinux = {
    expr = selected (homePackages "aarch64-linux" (fixtures.homeModule "common"));
    expected = [ "comfyui" ];
  };
}
