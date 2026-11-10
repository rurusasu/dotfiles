inputs:
let
  mkHome =
    system: platform:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = { inherit inputs platform; };
      modules = [ ./default.nix ];
    };
in
{
  aarch64-darwin = mkHome "aarch64-darwin" "darwin";
  x86_64-linux = mkHome "x86_64-linux" "linux";
  aarch64-linux = mkHome "aarch64-linux" "linux";
}
