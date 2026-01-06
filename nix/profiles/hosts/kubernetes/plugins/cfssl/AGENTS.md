# cfssl PKI Module

## Overview
This module provides HA-ready PKI (Public Key Infrastructure) for Kubernetes using cfssl (Cloudflare's PKI toolkit).

## Features
- Generates all required certificates for Kubernetes components
- Supports High Availability (HA) configurations via `extraSANs`
- Non-interactive certificate generation (suitable for systemd services)
- Automatic certificate generation on first boot

## Options

### `myKubernetes.pki.enable`
Enable cfssl-based PKI for Kubernetes.

### `myKubernetes.pki.extraSANs`
Extra Subject Alternative Names for certificates. Used for HA multi-master setups.

Example:
```nix
myKubernetes.pki = {
  enable = true;
  extraSANs = [ "10.0.0.10" "10.0.0.11" "master1.k8s.local" ];
};
```

## Generated Certificates
- CA certificate (`ca.pem`)
- API server (`kube-apiserver.pem`)
- Kubelet (`kubelet.pem`)
- Controller manager (`kube-controller-manager.pem`)
- Scheduler (`kube-scheduler.pem`)
- Kube-proxy (`kube-proxy.pem`)
- etcd (`etcd.pem`)
- Admin (`admin.pem`)
- Service account key pair

## Certificate Location
All certificates are stored in `/var/lib/kubernetes/secrets/`

## Kubeconfig
Cluster admin kubeconfig is generated at `/etc/kubernetes/cluster-admin.kubeconfig`

## Dependencies
- `services.kubernetes` must be configured
- Network must be available before certificate generation

## Why cfssl over easyCerts?
- `easyCerts = true` is simple but not suitable for HA configurations
- cfssl allows adding extra SANs for multi-master setups
- cfssl is fully non-interactive (unlike step-ca which requires interactive initialization)
