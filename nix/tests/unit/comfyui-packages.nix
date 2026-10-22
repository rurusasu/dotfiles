{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  desktop = import ../../modules/desktop.nix;
  selected =
    packages:
    map (package: package.pname) (
      builtins.filter (package: (package.pname or "") == "comfyui-desktop") packages
    );
  linuxPackages = system: scope: (fixtures.mkHome system [ scope ]).config.home.packages;
in
{
  testComfyDesktopIsInstalledForNativeLinuxAndWslg = {
    expr = {
      native = selected (linuxPackages "x86_64-linux" desktop.linuxDesktop);
      wsl = selected (linuxPackages "x86_64-linux" desktop.wslDesktop);
    };
    expected = {
      native = [ "comfyui-desktop" ];
      wsl = [ "comfyui-desktop" ];
    };
  };
  testComfyDesktopDoesNotSelectAnUnavailableArmLinuxBinary = {
    expr = selected (linuxPackages "aarch64-linux" desktop.linuxDesktop);
    expected = [ ];
  };
}
