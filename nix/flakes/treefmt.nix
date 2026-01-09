_: {
  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        package = pkgs.treefmt;
        enableDefaultExcludes = true;
        flakeFormatter = true;
        projectRootFile = "flake.nix";
      };
    };
}
