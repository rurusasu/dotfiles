{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  selected = import ./package.nix {
    inherit pkgs;
    release = import ./release.nix (builtins.fromJSON (builtins.readFile inputs.strata-release));
  };
in
{
  options.programs.strata.enable = lib.mkEnableOption "Strata desktop and control CLI";
  config = lib.mkIf config.programs.strata.enable {
    assertions = [
      {
        assertion = builtins.elem pkgs.stdenv.hostPlatform.system [
          "x86_64-linux"
          "aarch64-darwin"
        ];
        message = "Strata is supported on x86_64-linux and aarch64-darwin.";
      }
    ];
    home.packages = [
      selected.desktop
      selected.control
    ];
    home.activation =
      lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && config.targets.darwin.copyApps.enable)
        {
          strataProtectSignedBundle = lib.hm.dag.entryAfter [ "copyApps" ] ''
            strataAppDirectory=${lib.escapeShellArg "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Strata.app"}
            strataControlDirectory="$strataAppDirectory/Contents/Resources/control"
            # copyApps makes the bundle writable; Python would then replace its signed bytecode.
            # Failed cache writes are harmless: Python compiles imports in memory instead.
            if [[ -d "$strataControlDirectory" && ! -L "$strataAppDirectory" && ! -L "$strataControlDirectory" ]]; then
              run ${pkgs.coreutils}/bin/chmod -R a-w "$strataControlDirectory"
            fi
          '';
        };
  };
}
