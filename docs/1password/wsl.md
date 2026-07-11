# 1Password CLI on WSL

## 結論

WSL で Windows の 1Password app を使う場合は、Linux native の `op` ではなく
Windows 側の `op.exe` を使う。

この場合、実体は Windows CLI なので、非対話実行では Windows と同じく
`--cache=false` を付ける。

```bash
op.exe --cache=false read "op://Private/Example/credential" --account my.1password.com
```

```bash
printf '%s\n' "$template" | op.exe --cache=false inject --account my.1password.com
```

## env 継承

Windows launcher から WSL shell へ secret env を渡す場合は `WSLENV` を使う。

```cmd
set WSLENV=GITHUB_PAT_TOKEN:TAVILY_API_KEY:GITHUB_WORK_TOKEN
```

この repo の shell loader は、env が既に入っていれば抜ける。
env が不足していても `DOTFILES_FORCE_SECRET_LOAD` が無ければ、shell 起動時には
`op.exe` を呼ばない。`codex` などの wrapper が明示的に force したときだけ
`op.exe --cache=false read` で不足分を読む。

## 出力の CRLF

`op.exe` の出力を WSL shell の環境変数へ入れる場合は CR を落とす。

```bash
value="$(op.exe --cache=false read "$secret_ref" --account "$account")"
value="$(printf '%s' "$value" | tr -d '\r')"
```

## Native Linux `op` を使う場合

WSL 内に Linux 版 1Password と native `op` を入れている場合は [linux.md](./linux.md)
として扱う。Windows の 1Password app integration とは別の認証状態になる。

## SSH / Git

WSL では Windows の `op-ssh-sign.exe` をそのまま使うと payload や Linux path の扱いで
相性問題が出るため、この repo では wrapper を使う。

```gitconfig
[gpg "ssh"]
  program = ~/.local/bin/op-ssh-sign-wsl
```

SSH Agent socket は Linux 側のパスを使う。

```sshconfig
Host *
    IdentityAgent ~/.1password/agent.sock
```
