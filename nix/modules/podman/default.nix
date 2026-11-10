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
  config = lib.mkMerge [
    { services.podman.enable = true; }
    (lib.mkIf cfg.enable {
      # NixOS provides the public compatibility command through its standard option.
      home.packages = [
        pkgs.podman-compose
      ]
      ++ lib.optional (
        pkgs.stdenv.hostPlatform.isDarwin || !config.submoduleSupport.enable
      ) runtime.dockerCompat;
      services.podman.settings.containers.engine.compose_providers = [
        (lib.getExe pkgs.podman-compose)
      ];

      # Integrated NixOS homes use the units supplied by virtualisation.podman.
      systemd.user = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !config.submoduleSupport.enable) {
        sockets.podman = {
          Unit.Description = "Podman user API socket";
          Socket = {
            ListenStream = "%t/podman/podman.sock";
            SocketMode = "0600";
          };
          Install.WantedBy = [ "sockets.target" ];
        };
        services.podman = {
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
    })
  ];
}
