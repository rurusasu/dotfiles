{ inputs }:
let
  systemConfig = inputs.system-manager.lib.makeSystemConfig {
    modules = [
      {
        nixpkgs.hostPlatform = "x86_64-linux";
      }
      ../system-manager/docker.nix
    ];
  };
  config = systemConfig.config;
  dockerBuildx = config.nixpkgs.pkgs.docker-buildx;
in
{
  testSystemManagerDockerServiceAndSocketOptions = {
    expr = {
      serviceEnabled = config.systemd.services.docker.enable;
      serviceRequiresSocket = builtins.elem "docker.socket" config.systemd.services.docker.requires;
      serviceWantedBySystemManager = builtins.elem "system-manager.target" (
        config.systemd.services.docker.wantedBy
      );
      socketEnabled = config.systemd.sockets.docker.enable;
      socketMode = config.systemd.sockets.docker.socketConfig.SocketMode;
      socketGroup = config.systemd.sockets.docker.socketConfig.SocketGroup;
    };
    expected = {
      serviceEnabled = true;
      serviceRequiresSocket = true;
      serviceWantedBySystemManager = true;
      socketEnabled = true;
      socketMode = "0660";
      socketGroup = "docker";
    };
  };

  testSystemManagerInstallsDockerBuildx = {
    expr = builtins.elem dockerBuildx config.environment.systemPackages;
    expected = true;
  };
}
