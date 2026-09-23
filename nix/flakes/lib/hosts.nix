{ inputs }:
let
  selectHomeManagerUser = configuredUser: if configuredUser == "" then "nixos" else configuredUser;
  homeInstallFeatures = inputs.nixpkgs.lib.optionals (builtins.getEnv "DOTFILES_WITH_HERMES" == "1") [
    "WithHermes"
  ];
in
{
  inherit selectHomeManagerUser;

  mkNixosHostSpecs =
    {
      hardwareConfig ? builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG",
      requestedSystem ? builtins.getEnv "DOTFILES_SYSTEM",
    }:
    {
      nixos = {
        system = "x86_64-linux";
        hostPath = ../../hosts/wsl;
        homeModulePath = ../../home/wsl.nix;
      };
    }
    // (
      if hardwareConfig == "" then
        { }
      else
        {
          linux = {
            system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
            hostPath = ../../hosts/linux;
            homeModulePath = ../../home/linux.nix;
            inherit hardwareConfig;
          };
        }
    );

  mkNixos =
    {
      system,
      hostPath,
      siteLib,
      configuredUser ? builtins.getEnv "DOTFILES_USER",
      homeModulePath ? null,
      extraModules ? [ ],
      overlays ? [ ],
      homeExtraSpecialArgs ? { },
    }:
    let
      user = selectHomeManagerUser configuredUser;
    in
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs siteLib system; };
      modules = [
        { nixpkgs.hostPlatform = system; }
        hostPath
        { nixpkgs.overlays = overlays; }
        ../../modules/host
      ]
      ++ (
        if homeModulePath != null then
          [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                  installFeatures = homeInstallFeatures;
                }
                // homeExtraSpecialArgs;
                users.${user} = {
                  imports = [ homeModulePath ];
                };
              };
            }
          ]
        else
          [ ]
      )
      ++ extraModules;
    };
}
