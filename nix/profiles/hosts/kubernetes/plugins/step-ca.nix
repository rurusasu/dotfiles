{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.kubernetes;
  pkiCfg = config.myKubernetes.pki;
in
{
  options.myKubernetes.pki = {
    enable = mkEnableOption "step-ca based PKI for Kubernetes";

    caAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address for step-ca to listen on. Use 0.0.0.0 for HA multi-node setup.";
    };

    caPort = mkOption {
      type = types.port;
      default = 9443;
      description = "Port for step-ca to listen on.";
    };

    dnsNames = mkOption {
      type = types.listOf types.str;
      default = [ "localhost" "kubernetes" "kubernetes.default" "kubernetes.default.svc" ];
      description = "DNS names for the CA certificate.";
    };

    extraSANs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra Subject Alternative Names for certificates (IPs or DNS names for HA).";
      example = [ "10.0.0.10" "10.0.0.11" "10.0.0.12" "master1.k8s.local" ];
    };
  };

  config = mkIf pkiCfg.enable {
    # Install step-cli for certificate management
    environment.systemPackages = with pkgs; [
      step-cli
      step-ca
    ];

    # Configure Kubernetes to use our certificates
    services.kubernetes = {
      # CA certificate
      caFile = "/var/lib/kubernetes/secrets/ca.pem";

      # API server certificates
      apiserver = {
        tlsCertFile = "/var/lib/kubernetes/secrets/kube-apiserver.pem";
        tlsKeyFile = "/var/lib/kubernetes/secrets/kube-apiserver-key.pem";
        kubeletClientCaFile = "/var/lib/kubernetes/secrets/ca.pem";
        kubeletClientCertFile = "/var/lib/kubernetes/secrets/kube-apiserver.pem";
        kubeletClientKeyFile = "/var/lib/kubernetes/secrets/kube-apiserver-key.pem";
        serviceAccountSigningKeyFile = "/var/lib/kubernetes/secrets/service-account-key.pem";
        serviceAccountKeyFile = "/var/lib/kubernetes/secrets/service-account.pem";
        clientCaFile = "/var/lib/kubernetes/secrets/ca.pem";
      };

      # Controller manager certificates
      controllerManager = {
        serviceAccountKeyFile = "/var/lib/kubernetes/secrets/service-account-key.pem";
        rootCaFile = "/var/lib/kubernetes/secrets/ca.pem";
        kubeconfig = {
          caFile = "/var/lib/kubernetes/secrets/ca.pem";
          certFile = "/var/lib/kubernetes/secrets/kube-controller-manager.pem";
          keyFile = "/var/lib/kubernetes/secrets/kube-controller-manager-key.pem";
        };
      };

      # Scheduler certificates
      scheduler.kubeconfig = {
        caFile = "/var/lib/kubernetes/secrets/ca.pem";
        certFile = "/var/lib/kubernetes/secrets/kube-scheduler.pem";
        keyFile = "/var/lib/kubernetes/secrets/kube-scheduler-key.pem";
      };

      # Kubelet certificates
      kubelet = {
        clientCaFile = "/var/lib/kubernetes/secrets/ca.pem";
        tlsCertFile = "/var/lib/kubernetes/secrets/kubelet.pem";
        tlsKeyFile = "/var/lib/kubernetes/secrets/kubelet-key.pem";
        kubeconfig = {
          caFile = "/var/lib/kubernetes/secrets/ca.pem";
          certFile = "/var/lib/kubernetes/secrets/kubelet.pem";
          keyFile = "/var/lib/kubernetes/secrets/kubelet-key.pem";
        };
      };

      # Proxy certificates
      proxy.kubeconfig = {
        caFile = "/var/lib/kubernetes/secrets/ca.pem";
        certFile = "/var/lib/kubernetes/secrets/kube-proxy.pem";
        keyFile = "/var/lib/kubernetes/secrets/kube-proxy-key.pem";
      };
    };

    # Initialize step-ca certificates before the service starts
    systemd.services.step-ca-init = {
      description = "Initialize step-ca PKI for Kubernetes";
      wantedBy = [ "multi-user.target" ];
      before = [ "step-ca.service" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      path = [ pkgs.step-cli pkgs.step-ca ];

      script = let
        dnsNamesStr = concatStringsSep "," pkiCfg.dnsNames;
        allSANs = pkiCfg.dnsNames ++ pkiCfg.extraSANs;
      in ''
        CA_DIR="/var/lib/step-ca"
        STEP_PATH="/root/.step/authorities/kubernetes"
        mkdir -p "$CA_DIR/certs" "$CA_DIR/secrets" "$CA_DIR/db" "$CA_DIR/config"

        if [ ! -f "$CA_DIR/certs/root_ca.crt" ]; then
          echo "Initializing step-ca PKI..."

          # Initialize step-ca with kubernetes profile (non-interactive)
          export STEPPATH="$STEP_PATH"
          mkdir -p "$STEP_PATH"

          # Create password file first
          echo "kubernetes-pki-password" > "$STEP_PATH/password.txt"

          step ca init \
            --name="kubernetes-ca" \
            --dns="${dnsNamesStr}" \
            --address="${pkiCfg.caAddress}:${toString pkiCfg.caPort}" \
            --provisioner="kubernetes" \
            --password-file="$STEP_PATH/password.txt" \
            --provisioner-password-file="$STEP_PATH/password.txt" \
            --deployment-type=standalone \
            --no-db

          # Copy generated files from step's output directory to CA_DIR
          cp "$STEP_PATH/certs/root_ca.crt" "$CA_DIR/certs/"
          cp "$STEP_PATH/certs/intermediate_ca.crt" "$CA_DIR/certs/"
          cp "$STEP_PATH/secrets/root_ca_key" "$CA_DIR/secrets/"
          cp "$STEP_PATH/secrets/intermediate_ca_key" "$CA_DIR/secrets/"
          cp "$STEP_PATH/config/ca.json" "$CA_DIR/config/"
          cp "$STEP_PATH/config/defaults.json" "$CA_DIR/config/" 2>/dev/null || true

          echo "step-ca PKI initialized successfully"
        else
          echo "step-ca PKI already initialized"
        fi

        # Ensure proper permissions
        chown -R step-ca:step-ca "$CA_DIR"
        chmod 700 "$CA_DIR"
        chmod 600 "$CA_DIR/secrets/"* 2>/dev/null || true

        # Create password file for step-ca service
        echo "kubernetes-pki-password" > "$CA_DIR/password.txt"
        chmod 600 "$CA_DIR/password.txt"
        chown step-ca:step-ca "$CA_DIR/password.txt"
      '';
    };

    # step-ca service configuration
    # We use a custom systemd service instead of services.step-ca
    # because we need to use the ca.json generated by step ca init
    systemd.services.step-ca = {
      description = "step-ca service";
      wantedBy = [ "multi-user.target" ];
      after = [ "step-ca-init.service" "network.target" ];
      requires = [ "step-ca-init.service" ];

      serviceConfig = {
        Type = "simple";
        User = "step-ca";
        Group = "step-ca";
        ExecStart = "${pkgs.step-ca}/bin/step-ca /var/lib/step-ca/config/ca.json --password-file=/var/lib/step-ca/password.txt";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "step-ca";
      };
    };

    # Create step-ca user and group
    users.users.step-ca = {
      isSystemUser = true;
      group = "step-ca";
      home = "/var/lib/step-ca";
    };
    users.groups.step-ca = {};

    # Generate Kubernetes certificates using step-ca
    systemd.services.kubernetes-certs-init = {
      description = "Generate Kubernetes certificates from step-ca";
      wantedBy = [ "multi-user.target" ];
      after = [ "step-ca.service" ];
      before = [ "kube-apiserver.service" "etcd.service" "kubelet.service" ];
      requires = [ "step-ca.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [ pkgs.step-cli pkgs.openssl ];

      script = let
        allSANs = pkiCfg.dnsNames ++ pkiCfg.extraSANs ++ [ "127.0.0.1" "10.0.0.1" ];
        sansStr = concatStringsSep " " (map (san: "--san=${san}") allSANs);
      in ''
        SECRETS_DIR="/var/lib/kubernetes/secrets"
        CA_URL="https://${pkiCfg.caAddress}:${toString pkiCfg.caPort}"
        CA_ROOT="/var/lib/step-ca/certs/root_ca.crt"

        mkdir -p "$SECRETS_DIR"

        # Wait for step-ca to be ready
        for i in $(seq 1 30); do
          if step ca health --ca-url="$CA_URL" --root="$CA_ROOT" 2>/dev/null; then
            echo "step-ca is ready"
            break
          fi
          echo "Waiting for step-ca... ($i/30)"
          sleep 2
        done

        # Bootstrap step-cli to trust the CA
        step ca bootstrap \
          --ca-url="$CA_URL" \
          --fingerprint="$(step certificate fingerprint "$CA_ROOT")" \
          --install \
          --force

        # Generate API server certificate
        if [ ! -f "$SECRETS_DIR/kube-apiserver.pem" ]; then
          echo "Generating API server certificate..."
          step ca certificate \
            "kube-apiserver" \
            "$SECRETS_DIR/kube-apiserver.pem" \
            "$SECRETS_DIR/kube-apiserver-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            ${sansStr} \
            --not-after=8760h \
            --force
        fi

        # Generate kubelet certificate
        if [ ! -f "$SECRETS_DIR/kubelet.pem" ]; then
          echo "Generating kubelet certificate..."
          step ca certificate \
            "system:node:$(hostname)" \
            "$SECRETS_DIR/kubelet.pem" \
            "$SECRETS_DIR/kubelet-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            --san="$(hostname)" \
            --san="127.0.0.1" \
            --not-after=8760h \
            --force
        fi

        # Generate controller-manager certificate
        if [ ! -f "$SECRETS_DIR/kube-controller-manager.pem" ]; then
          echo "Generating controller-manager certificate..."
          step ca certificate \
            "system:kube-controller-manager" \
            "$SECRETS_DIR/kube-controller-manager.pem" \
            "$SECRETS_DIR/kube-controller-manager-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            --not-after=8760h \
            --force
        fi

        # Generate scheduler certificate
        if [ ! -f "$SECRETS_DIR/kube-scheduler.pem" ]; then
          echo "Generating scheduler certificate..."
          step ca certificate \
            "system:kube-scheduler" \
            "$SECRETS_DIR/kube-scheduler.pem" \
            "$SECRETS_DIR/kube-scheduler-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            --not-after=8760h \
            --force
        fi

        # Generate admin certificate for kubectl
        if [ ! -f "$SECRETS_DIR/admin.pem" ]; then
          echo "Generating admin certificate..."
          step ca certificate \
            "kubernetes-admin" \
            "$SECRETS_DIR/admin.pem" \
            "$SECRETS_DIR/admin-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            --not-after=8760h \
            --force
        fi

        # Generate kube-proxy certificate
        if [ ! -f "$SECRETS_DIR/kube-proxy.pem" ]; then
          echo "Generating kube-proxy certificate..."
          step ca certificate \
            "system:kube-proxy" \
            "$SECRETS_DIR/kube-proxy.pem" \
            "$SECRETS_DIR/kube-proxy-key.pem" \
            --ca-url="$CA_URL" \
            --root="$CA_ROOT" \
            --provisioner="kubernetes" \
            --provisioner-password-file="/var/lib/step-ca/password.txt" \
            --not-after=8760h \
            --force
        fi

        # Generate service account key pair (RSA for JWT signing)
        if [ ! -f "$SECRETS_DIR/service-account-key.pem" ]; then
          echo "Generating service account key pair..."
          openssl genrsa -out "$SECRETS_DIR/service-account-key.pem" 2048
          openssl rsa -in "$SECRETS_DIR/service-account-key.pem" -pubout -out "$SECRETS_DIR/service-account.pem"
        fi

        # Copy CA certificate
        cp "$CA_ROOT" "$SECRETS_DIR/ca.pem"

        # Set proper permissions
        chmod 600 "$SECRETS_DIR"/*-key.pem
        chmod 644 "$SECRETS_DIR"/*.pem
        chown -R kubernetes:kubernetes "$SECRETS_DIR"

        # Generate cluster-admin kubeconfig
        KUBECONFIG_DIR="/etc/kubernetes"
        mkdir -p "$KUBECONFIG_DIR"

        cat > "$KUBECONFIG_DIR/cluster-admin.kubeconfig" <<EOF
        apiVersion: v1
        kind: Config
        clusters:
        - cluster:
            certificate-authority: $SECRETS_DIR/ca.pem
            server: https://127.0.0.1:6443
          name: kubernetes
        contexts:
        - context:
            cluster: kubernetes
            user: kubernetes-admin
          name: kubernetes-admin@kubernetes
        current-context: kubernetes-admin@kubernetes
        users:
        - name: kubernetes-admin
          user:
            client-certificate: $SECRETS_DIR/admin.pem
            client-key: $SECRETS_DIR/admin-key.pem
        EOF

        chmod 600 "$KUBECONFIG_DIR/cluster-admin.kubeconfig"
        echo "Kubernetes certificates generated successfully"
      '';
    };

    # Ensure Kubernetes services depend on certificate generation
    systemd.services.etcd = {
      after = [ "kubernetes-certs-init.service" ];
      requires = [ "kubernetes-certs-init.service" ];
    };

    systemd.services.kube-apiserver = {
      after = [ "kubernetes-certs-init.service" ];
      requires = [ "kubernetes-certs-init.service" ];
    };

    systemd.services.kubelet = {
      after = [ "kubernetes-certs-init.service" ];
      requires = [ "kubernetes-certs-init.service" ];
    };
  };
}
