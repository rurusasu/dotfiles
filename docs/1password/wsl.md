# 1Password CLI on WSL

## Linux ネイティブ CLI を使う

WSL の `op` は Home Manager が `pkgs._1password-cli` から導入する Linux 実行ファイルです。
NixOS は `programs._1password.enable` で CLI 連携に必要な setgid wrapper を作成します。
通常の `op` は `/run/wrappers/bin/op` を使います。
Hermes の `secrets.onepassword.binary_path` もこのパスに固定し、サービスの PATH から
権限なしの store 内 CLI を直接起動しないようにします。
Linux 版 1Password の認証と app integration を使い、Windows の `op.exe` や Windows PATH に依存しません。
`~/.local/bin/op` に Windows へ転送する wrapper は配布しません。

```bash
command -v op
op --version
op account list
```

Linux 版 1Password へのサインインと CLI integration の設定は [Linux](./linux.md) を参照してください。
`op read` / `op inject` / `op run` は同じ Linux CLI を使います。
Windows CLI 固有の `--cache=false` や出力の CRLF 除去は WSL の標準経路では不要です。

## SSH / Git

WSL では Windows の `op-ssh-sign.exe` をそのまま使うと payload や Linux path の扱いで
相性問題が出るため、この repo では wrapper を使う。

```gitconfig
[gpg "ssh"]
  program = ~/.local/bin/op-ssh-sign-wsl
```

この Nix 構成の native `ssh` は WSL 内の Linux 版 1Password の agent socket を使う。`nix/modules/1password/ssh.nix` が `IdentityAgent` と `SSH_AUTH_SOCK` を同じパスに設定する。Windows の `op.exe` への CLI 連携や署名 wrapper は、この Linux socket を Windows agent に接続する仕組みではない。

Windows 版 1Password の agent を SSH 認証にも使う場合、[公式の WSL 連携](https://developer.1password.com/docs/ssh/integrations/wsl/)は Windows OpenSSH の `ssh.exe` を使う。既存の native `ssh` 経路を無断で置き換えず、この構成では Linux 版 agent の経路を維持する。

```sshconfig
Host *
    IdentityAgent ~/.1password/agent.sock
```
