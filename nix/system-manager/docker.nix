{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
    docker-buildx
  ];

  environment.etc."docker/daemon.json".text = builtins.toJSON {
    "log-driver" = "json-file";
    "log-opts" = {
      "max-size" = "10m";
      "max-file" = "3";
    };
  };

  systemd = {
    services.docker = {
      enable = true;
      description = "Docker Application Container Engine";
      documentation = [ "https://docs.docker.com" ];
      after = [
        "network-online.target"
        "firewalld.service"
        "containerd.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.socket" ];
      wantedBy = [ "system-manager.target" ];

      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.docker}/bin/dockerd --host=fd://";
        ExecReload = "/bin/kill -s HUP $MAINPID";
        TimeoutStartSec = 0;
        RestartSec = 2;
        Restart = "always";
        StartLimitBurst = 3;
        StartLimitInterval = "60s";
        LimitNOFILE = 1048576;
        LimitNPROC = "infinity";
        LimitCORE = "infinity";
        TasksMax = "infinity";
        Delegate = "yes";
        KillMode = "process";
        OOMScoreAdjust = -500;
      };
    };

    sockets.docker = {
      enable = true;
      description = "Docker Socket for the API";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/var/run/docker.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "docker";
      };
    };

    tmpfiles.rules = [
      "d /var/lib/docker 0710 root root -"
      "d /var/run/docker 0755 root root -"
      "d /etc/docker 0755 root root -"
    ];
  };
}
