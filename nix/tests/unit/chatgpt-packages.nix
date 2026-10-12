{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
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
  testChatGPTInstallationIsOwnedByModule = {
    expr = {
      darwin = builtins.elem pkgs.chatgpt (chatgpt "aarch64-darwin").home.packages;
      linux = (chatgpt "x86_64-linux").home.packages;
    };
    expected = {
      darwin = true;
      linux = [ ];
    };
  };

}
