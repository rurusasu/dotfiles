# 1Password CLI on macOS

## 結論

macOS native の `op` は UNIX-like 環境として扱う。
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

macOS の標準環境に GNU `timeout` が無い場合は、`gtimeout` など環境に合わせた
timeout 実装を使う。

## Chezmoi

`onepasswordRead` は使えるが、secret manager の応答に `chezmoi apply` 全体を
強く依存させる。通常は runtime の `op read` / `op inject` に寄せる。

## SSH / Git

macOS の SSH agent socket は 1Password Group Container の socket を使う。

```sshconfig
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

`gpg.ssh.program` は 1Password の signer を使う。

```gitconfig
[gpg "ssh"]
  program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign
```
