# Cilium CNI Plugin

## Overview
This module configures Cilium as the Container Network Interface (CNI) for Kubernetes.

## Features
- Installs `cilium-cli` and `hubble` CLI tools
- Prepares `/opt/cni/bin` directory for Cilium's CNI binary
- Configures systemd service ordering for kubelet

## Installation
Cilium is deployed via Helm after the cluster is running:

```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.16.5 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup
```

## Verification
```bash
cilium status
kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium
```

## Dependencies
- Kubernetes cluster must be running
- PKI certificates must be initialized (cfssl module)
