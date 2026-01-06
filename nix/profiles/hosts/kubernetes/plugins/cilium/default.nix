{ config, lib, pkgs, ... }:

{
  # Cilium CNI plugin for Kubernetes
  # This module manages the Cilium CNI binary installation

  # Install cilium-cli for managing Cilium
  environment.systemPackages = with pkgs; [
    cilium-cli
    hubble
  ];

  # Systemd service to install Cilium CNI binary
  # Cilium's CNI binary needs to be available in /opt/cni/bin for kubelet
  systemd.services.install-cilium-cni = {
    description = "Install Cilium CNI binary";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    before = [ "kubelet.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.kubernetes ];

    script = ''
      # Ensure CNI directory exists
      mkdir -p /opt/cni/bin

      # Note: The actual cilium-cni binary will be installed by Cilium's
      # init container when the Cilium DaemonSet is deployed.
      # This service just ensures the directory is ready and writable.

      # Set proper permissions
      chmod 755 /opt/cni/bin

      echo "CNI directory prepared for Cilium installation"
    '';
  };

  # Kubelet needs to wait for CNI setup
  systemd.services.kubelet = {
    after = [ "install-cilium-cni.service" ];
    requires = [ "install-cilium-cni.service" ];
  };
}
