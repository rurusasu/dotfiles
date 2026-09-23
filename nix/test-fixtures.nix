{ inputs }:
let
  workmux = import ./flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = workmux.mkOverlay (system: inputs.workmux.packages.${system}.default);
in
{
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ workmuxOverlay ];
    };
}
