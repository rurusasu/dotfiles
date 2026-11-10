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
      # Generate the GPU specification consumed by CDI-aware container runtimes.
      nvidiaCdi = {
        text = ''
          mkdir -p /etc/cdi
          ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk cdi generate \
            --output /etc/cdi/nvidia.yaml 2>/dev/null || true
        '';
      };
    };
  };
}
