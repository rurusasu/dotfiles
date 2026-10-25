{
  inputs,
  pkgs,
  chatgptDesktopCheck ? null,
}:
let
  buildPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
buildPkgs.linkFarm "custom-package-builds" (
  [
    {
      name = "orca-editor";
      path = inputs.llm-agents.packages.${buildPkgs.stdenv.hostPlatform.system}.orca;
    }
  ]
  ++ buildPkgs.lib.optionals (chatgptDesktopCheck != null) [
    {
      name = "chatgpt-desktop";
      path = chatgptDesktopCheck;
    }
  ]
  ++ buildPkgs.lib.optionals buildPkgs.stdenv.hostPlatform.isDarwin [
    {
      name = "dia-browser";
      path = import ../../../modules/browsers/dia {
        inherit inputs;
        pkgs = buildPkgs;
      };
    }
  ]
)
