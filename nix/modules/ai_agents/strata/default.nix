rec {
  packages =
    { pkgs, release }:
    import ./package.nix { inherit pkgs release; };

  homeManager =
    { pkgs, inputs, ... }:
    let
      selected = packages {
        inherit pkgs;
        release = import ./release.nix (builtins.fromJSON (builtins.readFile inputs.strata-release));
      };
    in
    {
      home.packages = [
        selected.desktop
        selected.control
      ];
    };
}
