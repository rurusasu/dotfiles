{ config, lib, pkgs, ... }:

{
  # Import plugins
  imports = [
    ./plugins/cilium.nix
    ./plugins/step-ca.nix
  ];

  # Enable step-ca based PKI for HA-ready certificate management
  myKubernetes.pki = {
    enable = true;
    # For HA setup, change caAddress to 0.0.0.0 and add extraSANs
    # caAddress = "0.0.0.0";
    # extraSANs = [ "10.0.0.10" "10.0.0.11" "master1.k8s.local" ];
  };

  # Kubernetes configuration
  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = "localhost";

    # Disable easyCerts - using step-ca for HA-ready PKI
    easyCerts = false;

    # Disable default flannel CNI (we'll use Cilium)
    flannel.enable = false;

    # API server configuration
    apiserver = {
      securePort = 6443;
      extraOpts = "--allow-privileged=true";
    };

    # Kubelet configuration for Cilium
    # Note: --network-plugin flag was removed in Kubernetes 1.24+
    # CNI is now the default and only network plugin. The cni-* flags
    # were removed from kubelet 1.34+, so rely on the defaults and
    # /opt/cni/bin symlinks below.
    kubelet.extraConfig = {
      # WSL typically runs with swap enabled; allow kubelet to start.
      failSwapOn = false;
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

  # Kernel parameters for Cilium/eBPF
  # Note: Kubernetes networking parameters (ip_forward, bridge-nf-call-*) are
  # automatically set by the Kubernetes module
  boot.kernel.sysctl = {
    "kernel.unprivileged_bpf_disabled" = 0;
    "net.core.bpf_jit_enable" = 1;
  };

  # Install kubectl, helm, and CNI plugins
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    cni-plugins
  ];

  # Ensure CNI directory exists
  systemd.tmpfiles.rules = [
    "d /etc/cni/net.d 0755 root root -"
    "d /opt/cni/bin 0755 root root -"
  ];

  # Docker Desktop's /Docker/host mount includes spaces in /proc/mounts and
  # breaks kubelet's mount parser on WSL. Unmount it before kubelet starts.
  systemd.services.kubelet.preStart = lib.mkBefore ''
    umount -l /Docker/host || true
  '';
}
