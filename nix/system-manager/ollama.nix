{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.ollama ];

  systemd.services.ollama = {
    enable = true;
    description = "Ollama local model server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "system-manager.target" ];
    environment.OLLAMA_HOST = "127.0.0.1:11434";
    serviceConfig = {
      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
