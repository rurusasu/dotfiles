{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
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
        value = linuxPkgs.callPackage ../../packages/chatgpt { };
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
    };
    expected = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "chatgpt";
        identity = {
          appName = "ChatGPT.app";
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
