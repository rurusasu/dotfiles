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
  testChatGPTPreservesDarwinProviderAndDisablesLinux = {
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
      linux.unsupported = "The Linux desktop app is not managed by this repository";
      windows = {
        unsupported = "The Windows Store app is intentionally excluded from this package catalog";
      };
    };
  };

}
