{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.ollama ];

  systemd.services.ollama = {
    enable = true;
    description = "Ollama local model server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "system-manager.target" ];
    # Docker reaches the host through its bridge gateway. The host firewall
    # must keep 11434 closed to external interfaces.
    environment.OLLAMA_HOST = "0.0.0.0:11434";
    serviceConfig = {
      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
