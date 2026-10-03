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
      packageId = sets.wingetMap._1password-cli;
      verifier = sets.wingetVerify._1password-cli;
    };
    expected = {
      packageId = "AgileBits.1Password.CLI";
      verifier = {
        command = "op";
        args = [ "--version" ];
      };
    };
  };
  testNeovimSoftwareIsAbsentFromCatalogAndWindowsProviders = {
    expr =
      builtins.all
        (
          name:
          !(builtins.hasAttr name sets.supportReport)
          && !(builtins.hasAttr name sets.wingetMap)
          && !(builtins.hasAttr name sets.wingetVerify)
        )
        [
          "neovim"
          "neovim-remote"
          "nixd"
          "ty"
          "ruff"
          "yaml-language-server"
          "taplo"
          "bash-language-server"
          "lua-language-server"
          "stylua"
          "marksman"
          "gopls"
          "rust-analyzer"
          "rustfmt"
          "astro-language-server"
          "oxlint"
          "typescript-language-server"
        ];
    expected = true;
  };
}
