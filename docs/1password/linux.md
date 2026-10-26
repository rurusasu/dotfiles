# 1Password CLI on Linux

## 結論

Linux native の `op` は UNIX-like 環境として扱う。
CLI help 上、caching は UNIX-like では既定で有効であり、Windows の
`--cache=false` ルールをそのまま適用しない。

NixOS は `programs._1password.enable` で `onepassword-cli` group と
`/run/wrappers/bin/op` の setgid wrapper を管理する。Home Manager の package 導入だけでは
デスクトップ連携に必要な権限が不足する。

Linux 版 1Password にサインインし、「設定 → 開発者 → CLI 連携」を有効にする。
`op read` の初回実行時にアクセス確認やロック解除が表示されたら、Linux 版アプリで操作する。
Hermes は NixOS の設定から `secrets.onepassword.binary_path` に wrapper を指定する。
Hermes の gateway / backend service は `NoNewPrivileges = false` と `PrivateTmp = false` に設定する。
前者の upstream 既定値は setgid を抑止し、後者はユーザーサービスでホストの
`onepassword-cli` GID を持たない user namespace を作るため、CLI 連携が拒否される。
この例外は NixOS の有効な Hermes service に限定する。

```bash
op read "op://Private/Example/credential" --account my.1password.com
```

```bash
printf '%s\n' "$template" | op inject --account my.1password.com
```

## timeout

shell startup や deploy script では、prompt や app integration 待ちで止まらないように
timeout を付ける。

```bash
timeout 180s op read "op://Private/Example/credential" --account my.1password.com
```

失敗しても続行したい箇所では warning / fallback を使う。
必須 secret なら明示的に失敗させる。

## Chezmoi

`onepasswordRead` は使えるが、secret manager の応答に `chezmoi apply` 全体を
強く依存させる。通常は runtime の `op read` / `op inject` に寄せる。

## SSH / Git

`nix/modules/1password/ssh.nix` が Linux デスクトップ版の SSH agent socket を `IdentityAgent` と `SSH_AUTH_SOCK` に設定する。実際のホームディレクトリから絶対パスを生成し、Bash の独自 agent 起動で上書きしない。

```sshconfig
Host *
    IdentityAgent ~/.1password/agent.sock
```

`gpg.ssh.program` は 1Password の signer を使う。

```gitconfig
[gpg "ssh"]
  program = /opt/1Password/op-ssh-sign
```
