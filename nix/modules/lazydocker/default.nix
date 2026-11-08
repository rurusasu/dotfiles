{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtime = import ../podman/runtime.nix { inherit pkgs; };
in
{
  config = lib.mkIf config.programs.lazydocker.enable {
    programs.lazydocker = {
      package = runtime.wrap pkgs.lazydocker "lazydocker";
      settings.commandTemplates.dockerCompose = lib.getExe pkgs.podman-compose;
    };
  };
}
