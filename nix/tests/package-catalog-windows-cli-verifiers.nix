{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
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

  testLuaLanguageServerUsesVersionVerifier = {
    expr = {
      packageId = sets.wingetMap.lua-language-server;
      verifier = sets.wingetVerify.lua-language-server;
    };
    expected = {
      packageId = "LuaLS.lua-language-server";
      verifier = {
        command = "lua-language-server";
        args = [ "--version" ];
      };
    };
  };

  testStyLuaUsesVersionVerifier = {
    expr = {
      packageId = sets.wingetMap.stylua;
      verifier = sets.wingetVerify.stylua;
    };
    expected = {
      packageId = "JohnnyMorganz.StyLua";
      verifier = {
        command = "stylua";
        args = [ "--version" ];
      };
    };
  };

  testRustAnalyzerUsesPortableExecutableVerifierAndLink = {
    expr = {
      packageId = sets.wingetMap.rust-analyzer;
      verifier = sets.wingetVerify.rust-analyzer;
      portableLink = sets.wingetPortableLinksById."Rustlang.rust-analyzer";
      pathEntries = sets.wingetPathEntries."Rustlang.rust-analyzer";
    };
    expected = {
      packageId = "Rustlang.rust-analyzer";
      verifier = {
        type = "portableLinkCommand";
        command = "rust-analyzer.exe";
        args = [ "--version" ];
      };
      portableLink = {
        linkName = "rust-analyzer.exe";
        targetPattern = "rust-analyzer.exe";
      };
      pathEntries = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Links" ];
    };
  };
}
