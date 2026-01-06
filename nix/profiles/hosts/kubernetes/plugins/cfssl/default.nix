{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.kubernetes;
  pkiCfg = config.myKubernetes.pki;
in
{
  options.myKubernetes.pki = {
    enable = mkEnableOption "cfssl based PKI for Kubernetes";

    extraSANs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra Subject Alternative Names for certificates (IPs or DNS names for HA).";
      example = [ "10.0.0.10" "10.0.0.11" "10.0.0.12" "master1.k8s.local" ];
    };
  };

  config = mkIf pkiCfg.enable {
    # Install cfssl for certificate management
    environment.systemPackages = with pkgs; [
      cfssl
      openssl
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
        # etcd client certificates
        etcd = {
          caFile = "/var/lib/kubernetes/secrets/ca.pem";
          certFile = "/var/lib/kubernetes/secrets/etcd.pem";
          keyFile = "/var/lib/kubernetes/secrets/etcd-key.pem";
        };
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

    # etcd TLS configuration
    services.etcd = {
      certFile = "/var/lib/kubernetes/secrets/etcd.pem";
      keyFile = "/var/lib/kubernetes/secrets/etcd-key.pem";
      trustedCaFile = "/var/lib/kubernetes/secrets/ca.pem";
      peerCertFile = "/var/lib/kubernetes/secrets/etcd.pem";
      peerKeyFile = "/var/lib/kubernetes/secrets/etcd-key.pem";
      peerTrustedCaFile = "/var/lib/kubernetes/secrets/ca.pem";
    };

    # Generate all Kubernetes certificates using cfssl
    systemd.services.kubernetes-pki-init = {
      description = "Initialize Kubernetes PKI with cfssl";
      wantedBy = [ "multi-user.target" ];
      before = [ "kube-apiserver.service" "etcd.service" "kubelet.service" "kube-controller-manager.service" "kube-scheduler.service" "kube-proxy.service" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [ pkgs.cfssl pkgs.openssl ];

      script = let
        # Build hosts list for certificates
        defaultHosts = [ "127.0.0.1" "localhost" "10.0.0.1" "kubernetes" "kubernetes.default" "kubernetes.default.svc" "kubernetes.default.svc.cluster.local" ];
        allHosts = defaultHosts ++ pkiCfg.extraSANs;
        hostsJson = builtins.toJSON allHosts;
      in ''
        SECRETS_DIR="/var/lib/kubernetes/secrets"
        mkdir -p "$SECRETS_DIR"

        # Only generate if CA doesn't exist
        if [ ! -f "$SECRETS_DIR/ca.pem" ]; then
          echo "Generating Kubernetes PKI certificates..."

          cd "$SECRETS_DIR"

          # Create CA config
          cat > ca-config.json <<'CACONFIG'
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
CACONFIG

          # Generate CA certificate
          cat > ca-csr.json <<'CACSR'
{
  "CN": "kubernetes-ca",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes"
    }
  ]
}
CACSR
          cfssl gencert -initca ca-csr.json | cfssljson -bare ca
          echo "CA certificate generated"

          # Generate API server certificate
          cat > kube-apiserver-csr.json <<APICSR
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "hosts": ${hostsJson},
  "names": [
    {
      "O": "Kubernetes"
    }
  ]
}
APICSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare kube-apiserver
          echo "API server certificate generated"

          # Generate kubelet certificate
          cat > kubelet-csr.json <<'KUBELETCSR'
{
  "CN": "system:node:nixos",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "hosts": ["127.0.0.1", "nixos"],
  "names": [
    {
      "O": "system:nodes"
    }
  ]
}
KUBELETCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubelet-csr.json | cfssljson -bare kubelet
          echo "Kubelet certificate generated"

          # Generate controller-manager certificate
          cat > kube-controller-manager-csr.json <<'CMCSR'
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:kube-controller-manager"
    }
  ]
}
CMCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
          echo "Controller manager certificate generated"

          # Generate scheduler certificate
          cat > kube-scheduler-csr.json <<'SCHEDCSR'
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:kube-scheduler"
    }
  ]
}
SCHEDCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler
          echo "Scheduler certificate generated"

          # Generate kube-proxy certificate
          cat > kube-proxy-csr.json <<'PROXYCSR'
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:node-proxier"
    }
  ]
}
PROXYCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
          echo "Kube-proxy certificate generated"

          # Generate etcd server certificate
          cat > etcd-csr.json <<ETCDCSR
{
  "CN": "etcd",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "hosts": ${hostsJson},
  "names": [
    {
      "O": "etcd"
    }
  ]
}
ETCDCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
          echo "etcd certificate generated"

          # Generate admin certificate
          cat > admin-csr.json <<'ADMINCSR'
{
  "CN": "kubernetes-admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:masters"
    }
  ]
}
ADMINCSR
          cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
          echo "Admin certificate generated"

          # Generate service account key pair (RSA for JWT signing)
          openssl genrsa -out service-account-key.pem 2048
          openssl rsa -in service-account-key.pem -pubout -out service-account.pem
          echo "Service account key pair generated"

          # Clean up CSR files
          rm -f *.csr *.json

          # Set proper permissions
          chmod 600 *-key.pem
          chmod 644 *.pem

          echo "Kubernetes PKI initialized successfully"
        else
          echo "Kubernetes PKI already initialized"
        fi

        # Ensure proper ownership
        chown -R kubernetes:kubernetes "$SECRETS_DIR" 2>/dev/null || true

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
        echo "Cluster admin kubeconfig generated"
      '';
    };

    # Ensure Kubernetes services depend on PKI initialization
    systemd.services.etcd = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };

    systemd.services.kube-apiserver = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };

    systemd.services.kube-controller-manager = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };

    systemd.services.kube-scheduler = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };

    systemd.services.kube-proxy = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };

    systemd.services.kubelet = {
      after = [ "kubernetes-pki-init.service" ];
      requires = [ "kubernetes-pki-init.service" ];
    };
  };
}
