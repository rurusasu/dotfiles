{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  chatgpt =
    system:
    let
      modulePkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
    in
    import ../../modules/ai_agents/chatgpt {
      pkgs = modulePkgs;
      inherit (modulePkgs) lib;
      config.home.homeDirectory = "/home/test-user";
    };
in
{
  testLinuxChatGPTDesktopKeepsTheAppProvidedCodex = {
    expr =
      builtins.all
        (
          system:
          let
            modulePkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
            packages = import ../../modules/ai_agents/chatgpt/packages.nix {
              inherit inputs;
              pkgs = modulePkgs;
            };
            upstream = import inputs.chatgpt-nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          in
          packages.chatgpt.drvPath == (upstream.chatgpt.override { codex = null; }).drvPath
        )
        [
          "x86_64-linux"
          "aarch64-linux"
        ];
    expected = true;
  };

  testChatGPTInstallationIsOwnedByModule = {
    expr = {
      catalogEntry = sets.supportReport ? chatgpt;
      darwin = builtins.elem pkgs.chatgpt (chatgpt "aarch64-darwin").home.packages;
      linux = (chatgpt "x86_64-linux").home.packages;
    };
    expected = {
      catalogEntry = false;
      darwin = true;
      linux = [ ];
    };
  };

}
