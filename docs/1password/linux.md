# 1Password CLI on Linux

## 結論

Linux native の `op` は UNIX-like 環境として扱う。
CLI help 上、caching は UNIX-like では既定で有効であり、Windows の
`--cache=false` ルールをそのまま適用しない。

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
timeout 60s op read "op://Private/Example/credential" --account my.1password.com
```

失敗しても続行したい箇所では warning / fallback を使う。
必須 secret なら明示的に失敗させる。

## Chezmoi

`onepasswordRead` は使えるが、secret manager の応答に `chezmoi apply` 全体を
強く依存させる。通常は runtime の `op read` / `op inject` に寄せる。

## SSH / Git

Linux の SSH agent socket は次を使う。

```sshconfig
Host *
    IdentityAgent ~/.1password/agent.sock
```

`gpg.ssh.program` は 1Password の signer を使う。

```gitconfig
[gpg "ssh"]
  program = /opt/1Password/op-ssh-sign
```
