{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  linuxSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  chatgptBySystem = builtins.listToAttrs (
    map (
      system:
      let
        linuxPkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        name = system;
        value = linuxPkgs.callPackage ../packages/chatgpt { };
      }
    ) linuxSystems
  );
in
{
  testChatGPTPreservesDarwinAndLinuxProviderIdentities = {
    expr = {
      darwin = sets.supportReport.chatgpt.darwin;
      linux = sets.supportReport.chatgpt.linux;
      windows = sets.supportReport.chatgpt.windows;
      legacyDarwin = sets.supportReport.chatgpt.legacyDarwin;
    };
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "chatgpt";
        identity = {
          homepage = "https://openai.com/chatgpt/desktop/";
          appName = "ChatGPT.app";
          bundleId = "com.openai.codex";
          executable = "ChatGPT";
        };
      };
      linux = {
        provider = "nix";
        source = "dotfiles";
        identity = "chatgpt";
        nixAttr = "chatgpt";
      };
      windows = {
        unsupported = "The Windows Store app is intentionally excluded from this package catalog";
      };
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "chatgpt";
      };
    };
  };

  testChatGPTClassicHasNoCatalogOrMicrosoftStoreProviderID = {
    expr = {
      catalogEntry = builtins.hasAttr "9NT1R1C2HH7J" sets.supportReport;
      mappedProviderId = builtins.elem "9NT1R1C2HH7J" (builtins.attrValues sets.msstoreMap);
      windowsOnlyProviderId = builtins.elem "9NT1R1C2HH7J" sets.windowsOnly.msstore;
    };
    expected = {
      catalogEntry = false;
      mappedProviderId = false;
      windowsOnlyProviderId = false;
    };
  };

  testChatGPTLinuxDerivationPreservesPinnedSourceUrlsAndHashes = {
    expr = builtins.mapAttrs (_: package: {
      url = package.src.url;
      hash = package.src.outputHash;
    }) chatgptBySystem;
    expected = {
      x86_64-linux = {
        url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.818.41705_amd64.deb";
        hash = "sha256-ySfJhVd73luszsx38C4UsxHZTmIwFWYh+vkleawDalU=";
      };
      aarch64-linux = {
        url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.818.41705_arm64.deb";
        hash = "sha256-Y3WtHooJT3Z5HiC58xyIhxnOz6E/Ct0sS7yAlgb3NIE=";
      };
    };
  };
}
