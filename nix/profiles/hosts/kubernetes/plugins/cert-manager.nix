{ config, lib, pkgs, ... }:

{
  # cert-manager for production-grade certificate management
  # This replaces easyCerts with a more robust solution
  #
  # NOTE: Currently disabled. This configuration is for future reference
  # when migrating from easyCerts to manual certificate management.
  # For GKE validation environment, easyCerts is sufficient.

  # Install cert-manager CLI tool
  environment.systemPackages = with pkgs; [
    cmctl  # cert-manager CLI
  ];

  # Generate self-signed CA certificate for the cluster
  # In production, you would use a proper CA or external PKI
  systemd.services.kubernetes-ca-init = {
    description = "Initialize Kubernetes CA certificates";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    before = [ "kube-apiserver.service" "etcd.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.openssl pkgs.kubernetes ];

    script = ''
      SECRETS_DIR="/var/lib/kubernetes/secrets"
      mkdir -p "$SECRETS_DIR"

      # Generate CA certificate if it doesn't exist
      if [ ! -f "$SECRETS_DIR/ca.pem" ]; then
        echo "Generating self-signed CA certificate..."

        # Generate CA private key
        openssl genrsa -out "$SECRETS_DIR/ca-key.pem" 4096

        # Generate CA certificate
        openssl req -x509 -new -nodes \
          -key "$SECRETS_DIR/ca-key.pem" \
          -sha256 -days 3650 \
          -out "$SECRETS_DIR/ca.pem" \
          -subj "/CN=kubernetes-ca/O=kubernetes"

        chmod 600 "$SECRETS_DIR/ca-key.pem"
        chmod 644 "$SECRETS_DIR/ca.pem"

        echo "CA certificate generated successfully"
      else
        echo "CA certificate already exists"
      fi

      # Generate API server certificate
      if [ ! -f "$SECRETS_DIR/kube-apiserver.pem" ]; then
        echo "Generating API server certificate..."

        # Create OpenSSL config for API server
        cat > "$SECRETS_DIR/apiserver-csr.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.0.0.1
EOF

        # Generate API server private key
        openssl genrsa -out "$SECRETS_DIR/kube-apiserver-key.pem" 2048

        # Generate API server CSR
        openssl req -new \
          -key "$SECRETS_DIR/kube-apiserver-key.pem" \
          -out "$SECRETS_DIR/kube-apiserver.csr" \
          -subj "/CN=kube-apiserver/O=kubernetes" \
          -config "$SECRETS_DIR/apiserver-csr.conf"

        # Sign API server certificate with CA
        openssl x509 -req \
          -in "$SECRETS_DIR/kube-apiserver.csr" \
          -CA "$SECRETS_DIR/ca.pem" \
          -CAkey "$SECRETS_DIR/ca-key.pem" \
          -CAcreateserial \
          -out "$SECRETS_DIR/kube-apiserver.pem" \
          -days 365 \
          -extensions v3_req \
          -extfile "$SECRETS_DIR/apiserver-csr.conf"

        chmod 600 "$SECRETS_DIR/kube-apiserver-key.pem"
        chmod 644 "$SECRETS_DIR/kube-apiserver.pem"

        rm -f "$SECRETS_DIR/kube-apiserver.csr" "$SECRETS_DIR/apiserver-csr.conf"

        echo "API server certificate generated successfully"
      else
        echo "API server certificate already exists"
      fi

      # Set proper ownership
      chown -R kubernetes:kubernetes "$SECRETS_DIR"
    '';
  };

  # Ensure etcd service depends on CA initialization
  systemd.services.etcd = {
    after = [ "kubernetes-ca-init.service" ];
    requires = [ "kubernetes-ca-init.service" ];
  };

  # Ensure API server depends on CA initialization
  systemd.services.kube-apiserver = {
    after = [ "kubernetes-ca-init.service" ];
    requires = [ "kubernetes-ca-init.service" ];
  };
}
