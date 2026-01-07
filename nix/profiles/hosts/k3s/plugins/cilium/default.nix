{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Install Cilium CLI tools
  environment.systemPackages = with pkgs; [
    cilium-cli
    hubble
  ];

  # Ensure CNI directories exist (k3s manages most of this)
  systemd.tmpfiles.rules = [
    "d /etc/cni/net.d 0755 root root -"
  ];

  # Systemd service to install Cilium after k3s is ready
  systemd.services.install-cilium = {
    description = "Install Cilium CNI for k3s";
    after = [ "k3s.service" ];
    wants = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };

    path = with pkgs; [
      cilium-cli
      kubectl
    ];

    script = ''
      # Wait for k3s API to be ready
      echo "Waiting for k3s API server..."
      until ${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes &>/dev/null; do
        echo "Waiting for k3s API..."
        sleep 5
      done

      # Check if Cilium is already installed
      if ${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get daemonset -n kube-system cilium &>/dev/null; then
        echo "Cilium already installed"
        exit 0
      fi

      # Install Cilium
      echo "Installing Cilium CNI..."
      ${pkgs.cilium-cli}/bin/cilium install \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=false \
        --set cgroup.autoMount.enabled=false \
        --set cgroup.hostRoot=/sys/fs/cgroup \
        --kubeconfig=/etc/rancher/k3s/k3s.yaml

      echo "Cilium installation complete"
    '';
  };
}
