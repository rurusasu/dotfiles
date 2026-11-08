{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.podman;
  runtime = import ./runtime.nix { inherit pkgs; };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      runtime.dockerCompat
      pkgs.podman-compose
    ];
    services.podman.settings.containers.engine.compose_providers = [
      (lib.getExe pkgs.podman-compose)
    ];

    # NixOS supplies these units system-wide; declare them for standalone homes too.
    systemd.user.sockets.podman = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Podman user API socket";
      Socket = {
        ListenStream = "%t/podman/podman.sock";
        SocketMode = "0600";
      };
      Install.WantedBy = [ "sockets.target" ];
    };
    systemd.user.services.podman = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "Podman user API service";
        Requires = [ "podman.socket" ];
        After = [ "podman.socket" ];
      };
      Service = {
        Type = "exec";
        ExecStart = "${lib.getExe cfg.package} system service --time=0";
        KillMode = "process";
      };
    };
  };
}
