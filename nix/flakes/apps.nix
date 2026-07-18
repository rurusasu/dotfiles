{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      apps =
        lib.optionalAttrs pkgs.stdenv.isDarwin {
          darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          system-manager.program =
            lib.getExe' inputs.system-manager.packages.${system}.default
              "system-manager";
        };
    };
}
