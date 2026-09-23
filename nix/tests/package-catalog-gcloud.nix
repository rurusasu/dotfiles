{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testGoogleCloudSdkUsesSharedInstallTimeoutAndPathEntries = {
    expr = {
      installTimeoutSeconds = sets.packageInstallTimeoutSeconds;
      packageTimeoutOverrides = sets.wingetInstallTimeoutSeconds;
      pathEntries = sets.wingetPathEntries."google-cloud-sdk";
    };
    expected = {
      installTimeoutSeconds = 900;
      packageTimeoutOverrides = { };
      pathEntries = [
        "%ProgramFiles%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
        "%ProgramFiles(x86)%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
        "%LOCALAPPDATA%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
      ];
    };
  };
}
