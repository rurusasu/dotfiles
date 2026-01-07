# Kubernetes Profile

NixOS WSL環境でのKubernetes with Cilium CNI構成。

## Overview

GKE検証環境として使用するためのKubernetesクラスタ設定。

### 主要コンポーネント

- **Kubernetes**: v1.34.3
- **CNI**: Cilium v1.18.2
- **Container Runtime**: containerd v2.2.1
- **Certificate Management**: easyCerts (開発/検証環境向け)

## Architecture

```
kubernetes/
├── default.nix              # メインKubernetes設定
└── plugins/
    ├── cilium.nix           # Cilium CNIプラグイン管理
    └── cert-manager.nix     # 将来の本番環境用（現在無効）
```

## Configuration Details

### Kubernetes設定 (default.nix)

- **Roles**: master + node (単一ノードクラスタ)
- **easyCerts**: 有効 (自動証明書管理)
- **Flannel**: 無効 (Ciliumを使用)
- **API Server**: ポート6443、特権コンテナ許可
- **Kubelet**: swap有効環境対応 (`failSwapOn: false`)

### Cilium設定 (plugins/cilium.nix)

- **IPAM Mode**: kubernetes
- **CNI Binary Path**: `/opt/cni/bin` (WSL対応)
- **CNI Config Path**: `/etc/cni/net.d`
- **systemd Service**: `install-cilium-cni.service` - CNIディレクトリ準備

### eBPF/Cilium対応

#### カーネルモジュール
- `br_netfilter`, `ip_vs`, `ip_vs_rr`, `ip_vs_wrr`, `ip_vs_sh`, `nf_conntrack`

#### カーネルパラメータ
- `kernel.unprivileged_bpf_disabled = 0`
- `net.core.bpf_jit_enable = 1`

## Installation History

### 2026-01-06: 初期セットアップとトラブルシューティング

#### 遭遇した問題と解決策

1. **sysctl重複定義エラー**
   - **問題**: `net.bridge.bridge-nf-call-*`, `net.ipv4.ip_forward` がKubernetesモジュールと重複
   - **解決**: 手動設定を削除（Kubernetesモジュールが自動設定）

2. **非推奨フラグエラー**
   - **問題**: `--network-plugin=cni` フラグはKubernetes 1.24+で削除済み
   - **解決**: kubelet.extraOptsから削除
   - **問題**: `--cni-conf-dir`, `--cni-bin-dir` フラグはKubernetes 1.34+で削除済み
   - **解決**: kubelet.extraConfigに移行（ただし最終的には削除）

3. **CNIバイナリパス問題**
   - **問題**: Ciliumが `/host/opt/cni/bin` にインストールしようとするがWSLでは `/host` プレフィックス不要
   - **解決**: `cilium install --set cni.binPath=/opt/cni/bin --set cni.confPath=/etc/cni/net.d`

4. **CNIバイナリ上書き問題**
   - **問題**: NixOSのactivation scriptがシンボリックリンクを作成してCiliumのバイナリを上書き
   - **解決**: activation scriptを削除、Ciliumの init container に完全に委任

5. **WSL固有の問題**
   - **問題**: Docker Desktop の `/Docker/host` マウントがkubeletのパーサーを破壊
   - **解決**: kubelet起動前に `umount -l /Docker/host` を実行

#### デプロイメント手順

```bash
# 1. NixOS設定適用
sudo nixos-rebuild switch --flake .#nixos

# 2. Ciliumインストール（正しいパスで）
sudo KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig cilium install \
  --set ipam.mode=kubernetes \
  --set cni.binPath=/opt/cni/bin \
  --set cni.confPath=/etc/cni/net.d

# 3. ステータス確認
sudo KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig cilium status
sudo KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig kubectl get nodes
sudo KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig kubectl get pods -A
```

## Verification

### クラスタステータス確認

```bash
# ノード状態
kubectl get nodes
# 期待値: nixos Ready

# ポッド状態
kubectl get pods -A
# 期待値:
# - cilium: Running
# - cilium-envoy: Running
# - cilium-operator: Running
# - coredns: Running

# Ciliumステータス
cilium status
# 期待値: すべてのコンポーネントがOK
```

## Notes

### easyCertsについて

現在の構成では **easyCerts を有効化** しています。

- **理由**: GKE検証環境として使用するため、証明書管理の自動化が適切
- **注意**: 本番環境では cert-manager や外部PKI を使用すべき
- **将来**: `plugins/cert-manager.nix` に手動証明書管理の参考実装あり

### WSL制限事項

- swap無効化が困難なため `failSwapOn: false` を設定
- Docker Desktop マウントとの干渉を回避する必要あり
- `/host` プレフィックスは不要（ホストパスがそのままマウントされる）

## Troubleshooting

### CNIバイナリが見つからない

```bash
# 症状: "failed to find plugin cilium-cni in path [/opt/cni/bin]"

# 確認
ls -la /opt/cni/bin/cilium-cni

# 修正: Ciliumポッドを再起動
kubectl delete pod -n kube-system -l k8s-app=cilium
```

### ノードがNotReady

```bash
# Ciliumステータス確認
cilium status

# Ciliumログ確認
kubectl logs -n kube-system -l k8s-app=cilium
```

## Future Improvements

1. **証明書管理**: cert-manager導入（本番環境移行時）
2. **モニタリング**: Prometheus + Grafana
3. **Hubble**: Ciliumネットワーク可観測性の有効化
4. **マルチノード**: 複数WSLインスタンスでクラスタ構成

## References

- [NixOS Kubernetes Module](https://search.nixos.org/options?query=services.kubernetes)
- [Cilium Installation](https://docs.cilium.io/en/stable/installation/)
- [Kubernetes on WSL Best Practices](https://kubernetes.io/blog/2020/05/21/wsl-docker-kubernetes-on-the-windows-desktop/)
