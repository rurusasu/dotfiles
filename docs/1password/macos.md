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

runtime deploy の secret read は最大 180 秒待ち、失敗した場合は warning / fallback に進む。

macOS の標準環境に GNU `timeout` が無い場合は、`gtimeout` など環境に合わせた
timeout 実装を使う。

## Desktop app integration

この環境では Home Manager と macOS installer が
`OP_BIOMETRIC_UNLOCK_ENABLED=true` を設定し、native `op` が1Password desktop app
の既存アカウントを利用できるようにする。初回だけ、1Passwordを開いてロック解除し、
Settings > Developer > Integrate with 1Password CLI を有効にする。複数accountを使う場合は、
引き続き各コマンドで `--account` を明示する。

## Chezmoi

`onepasswordRead` は使えるが、secret manager の応答に `chezmoi apply` 全体を
強く依存させる。通常は runtime の `op read` / `op inject` に寄せる。

## SSH / Git

`nix/modules/1password/ssh.nix` が macOS の 1Password Group Container の socket を `IdentityAgent` と `SSH_AUTH_SOCK` に設定する。空白を含むパスは SSH 設定で引用し、Bash の独自 agent 起動で上書きしない。

Darwin host は同じ値を `launchd.user.envVariables.SSH_AUTH_SOCK` に渡し、反映後に起動する GUI アプリも 1Password agent を使う。GnuPG の SSH agent 連携は Home Manager / system とも無効化する。macOS 標準 agent のプロセス停止・システム plist の変更は行わない。

```sshconfig
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

`gpg.ssh.program` は 1Password の signer を使う。

```gitconfig
[gpg "ssh"]
  program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign
```
