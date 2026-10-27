{ config, lib, ... }:
{
  config = lib.mkIf config.virtualisation.docker.enable {
    # kind nodes use the in-cluster Zot mirror for registry.localhost.
    environment.etc = lib.mkIf (config ? wsl && config.wsl.enable) {
      "containerd/certs.d/registry.localhost/hosts.toml".text = ''
        server = "http://registry.localhost"

        [host."http://zot.infra.svc.cluster.local:5080"]
          capabilities = ["pull", "resolve"]
      '';
    };
    # Preserve the existing native NixOS and WSL daemon policies.
    virtualisation.docker = {
      daemon.settings =
        if config ? wsl && config.wsl.enable then
          { insecure-registries = [ "registry.localhost" ]; }
        else
          {
            "log-driver" = "json-file";
            "log-opts" = {
              "max-size" = "10m";
              "max-file" = "3";
            };
          };
    };
  };
}
