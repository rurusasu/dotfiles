{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testGoogleCloudSdkUsesGcloudVersionVerifier = {
    expr = {
      packageId = sets.wingetMap.google-cloud-sdk;
      verifier = sets.wingetVerify.google-cloud-sdk;
    };
    expected = {
      packageId = "Google.CloudSDK";
      verifier = {
        command = "gcloud";
        args = [ "version" ];
      };
    };
  };

  testGitHubCliUsesPackageScopedVerifierTimeout = {
    expr = {
      packageId = sets.wingetMap.gh;
      verifier = sets.wingetVerify.gh;
    };
    expected = {
      packageId = "GitHub.cli";
      verifier = {
        command = "gh";
        args = [ "--version" ];
        timeoutSeconds = 60;
      };
    };
  };

  testGoUsesPackageScopedVerifierTimeout = {
    expr = {
      packageId = sets.wingetMap.go;
      verifier = sets.wingetVerify.go;
      usesSharedTimeout = sets.wingetVerify.go.timeoutSeconds == sets.packageInstallTimeoutSeconds;
    };
    expected = {
      packageId = "GoLang.Go";
      verifier = {
        command = "go";
        args = [ "version" ];
        timeoutSeconds = 3600;
      };
      usesSharedTimeout = true;
    };
  };

  testOnePasswordCliUsesOpVersionVerifier = {
    expr = {
      selected = builtins.elem "AgileBits.1Password.CLI" sets.windowsOnly.winget;
      verifier = sets.wingetVerifyById."AgileBits.1Password.CLI";
    };
    expected = {
      selected = true;
      verifier = {
        command = "op";
        args = [ "--version" ];
      };
    };
  };
}
