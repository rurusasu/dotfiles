{ pkgs, ... }:
let
  ollamaServe = pkgs.writeShellScript "ollama-serve-on-docker-gateway" ''
    docker_gateway="$(${pkgs.iproute2}/bin/ip -4 -o addr show dev docker0 | ${pkgs.gawk}/bin/awk '{ sub(/\/.*/, "", $4); print $4; exit }')"
    if [ -z "$docker_gateway" ]; then
      echo "Unable to resolve the Docker bridge gateway for Ollama." >&2
      exit 1
    fi
    export OLLAMA_HOST="$docker_gateway:11434"
    exec ${pkgs.ollama}/bin/ollama serve
  '';
in
{
  environment.systemPackages = [ pkgs.ollama ];

  systemd.services.ollama = {
    enable = true;
    description = "Ollama local model server";
    after = [
      "network-online.target"
      "docker.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      ExecStart = ollamaServe;
      Restart = "always";
      RestartSec = 2;
    };
  };
}
