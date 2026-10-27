{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.dotfiles.wslGpu.enable = lib.mkEnableOption "WSL NVIDIA container integration";
  config = lib.mkIf config.dotfiles.wslGpu.enable {
    environment.systemPackages = [ pkgs.nvidia-container-toolkit ];
    system.activationScripts = {
      wslWhoami.text = ''
        mkdir -p /usr/bin
        ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami
      '';
      # kind worker nodes mount /etc/cdi to expose GPUs through containerd.
      nvidiaCdi = {
        deps = [ "wslWhoami" ];
        text = ''
          mkdir -p /etc/cdi
          ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk cdi generate \
            --output /etc/cdi/nvidia.yaml 2>/dev/null || true
        '';
      };
    };
  };
}
