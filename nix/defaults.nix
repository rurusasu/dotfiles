# Flake output assembly and configuration registration.
inputs: {
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      apps =
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
          }
        else
          {
            home-manager.program = lib.getExe inputs.home-manager.packages.${system}.home-manager;
          };
    };

  configurations = (import ./hosts/configurations.nix inputs) // {
    homeConfigurations = import ./home/configurations.nix inputs;
  };
}
