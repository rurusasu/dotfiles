{ config, lib, pkgs, ... }:

{
  # Import Cilium plugin
  imports = [
    ./plugins/cilium
  ];

  # k3s server configuration
  services.k3s = {
    enable = true;
    role = "server";

    # Disable built-in flannel - we use Cilium
    extraFlags = [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable=traefik"                    # Disable default ingress
      "--write-kubeconfig-mode=644"          # Allow reading kubeconfig
      "--tls-san=localhost"                  # For HA-ready setup
      "--tls-san=127.0.0.1"
      "--tls-san=kubernetes"
      "--tls-san=kubernetes.default"
      # Add more SANs for HA: "--tls-san=10.0.0.10" "--tls-san=master1.local"
      "--kube-apiserver-arg=allow-privileged=true"
      "--kubelet-arg=fail-swap-on=false"     # WSL swap handling
    ];
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

  # Kernel parameters for Cilium/eBPF
  boot.kernel.sysctl = {
    "kernel.unprivileged_bpf_disabled" = 0;
    "net.core.bpf_jit_enable" = 1;
  };

  # Install kubectl, helm, and management tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s                                      # Optional: nice TUI for k8s
  ];

  # WSL-specific workaround: Docker Desktop mount breaks kubelet
  systemd.services.k3s.preStart = lib.mkBefore ''
    umount -l /Docker/host 2>/dev/null || true
  '';

  # Ensure k3s starts after network is ready
  systemd.services.k3s.after = [ "network-online.target" ];
  systemd.services.k3s.wants = [ "network-online.target" ];
}
