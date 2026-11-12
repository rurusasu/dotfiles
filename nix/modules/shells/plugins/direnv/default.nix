{
  config,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    { programs.direnv.enable = true; }
    (lib.mkIf config.programs.direnv.enable {
      programs.direnv = {
        enableBashIntegration = true;
        enableZshIntegration = true;
        # .envrc uses `use flake`; keep the flake loader independent of the
        # upstream default in Home Manager.
        nix-direnv.enable = true;
      };
    })
  ];
}
