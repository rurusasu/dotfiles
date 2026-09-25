{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  packageId = "Microsoft.VisualStudio.2022.BuildTools";
in
{
  testVisualStudioBuildToolsCatalogContract = {
    expr = {
      windowsOnly = builtins.elem packageId sets.windowsOnly.winget;
      requiresAdmin = sets.wingetRequiresAdmin.${packageId} or false;
      installTimeoutSeconds =
        sets.wingetInstallTimeoutSeconds.${packageId} or sets.packageInstallTimeoutSeconds;
      verifyCommand = sets.wingetVerifyById.${packageId};
      installArgs = sets.wingetInstallArgs.${packageId};
    };
    expected = {
      windowsOnly = true;
      requiresAdmin = true;
      installTimeoutSeconds = 900;
      verifyCommand = {
        type = "visualStudioInstanceVersion";
        command = "Microsoft.VisualStudio.Product.BuildTools";
        productId = "Microsoft.VisualStudio.Product.BuildTools";
        minimumVersion = "17.0";
        requiredComponent = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64";
        compilerRelativePath = "VC\\Tools\\MSVC\\*\\bin\\Hostx64\\x64\\cl.exe";
      };
      installArgs = [
        "--override"
        "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart"
      ];
    };
  };
}
