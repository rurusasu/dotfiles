{ config, lib, pkgs, ... }:

{
  # Kubernetes configuration
  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = "localhost";

    # Disable default flannel CNI (we'll use Cilium)
    flannel.enable = false;

    # API server configuration
    apiserver = {
      securePort = 6443;
      extraOpts = "--allow-privileged=true";
    };

    # Kubelet configuration for Cilium
    kubelet = {
      extraOpts = lib.concatStringsSep " " [
        "--network-plugin=cni"
        "--cni-conf-dir=/etc/cni/net.d"
        "--cni-bin-dir=${pkgs.cni-plugins}/bin"
      ];
    };

    # Add CNI plugins path
    path = [ pkgs.cni-plugins ];
  };

  # Required kernel modules for Cilium/eBPF
  boot.kernelModules = [
    "br_netfilter"
    "ip_vs"
    "ip_vs_rr"
    "ip_vs_wrr"
    "ip_vs_sh"
    "nf_conntrack"
  ];

  # Kernel parameters for Kubernetes and Cilium
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # eBPF related
    "kernel.unprivileged_bpf_disabled" = 0;
    "net.core.bpf_jit_enable" = 1;
  };

  # Install kubectl, helm, and cilium-cli
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    cilium-cli
    hubble
    cni-plugins
  ];

  # Ensure CNI directory exists
  systemd.tmpfiles.rules = [
    "d /etc/cni/net.d 0755 root root -"
    "d /opt/cni/bin 0755 root root -"
  ];

  # Link CNI plugins
  system.activationScripts.cniPlugins = {
    text = ''
      mkdir -p /opt/cni/bin
      for plugin in ${pkgs.cni-plugins}/bin/*; do
        ln -sf $plugin /opt/cni/bin/
      done
    '';
  };
}
