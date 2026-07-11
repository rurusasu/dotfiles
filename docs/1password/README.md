# 1Password CLI 運用

このリポジトリでは、実シークレットは 1Password に置き、dotfiles には
`op://...` 参照、非秘密設定、取得手順だけを置く。

## OS 別の入口

- [Windows](./windows.md)
- [WSL](./wsl.md)
- [Linux](./linux.md)
- [macOS](./macos.md)

## 共通ルール

1. 実シークレット、token、API key、cookie、pairing token はコミットしない。
2. 複数 1Password account があるため、`op` には `--account` を明示する。
3. `op read` / `op inject` / `op run` は用途を分ける。
4. `chezmoi` の template 描画中に secret manager へ強く依存させない。
5. 失敗しても apply や shell / GUI 起動を止めたくない箇所では、timeout と fallback を用意する。
6. shell / GUI 起動だけでは `op` を呼ばない。secret が必要なコマンドの wrapper で明示的に読む。

## Chezmoi との使い分け

`chezmoi` には `onepasswordRead` などの 1Password template 関数がある。
この機能自体は有効だが、この repo では通常の `.tmpl` から直接呼ばない。

理由:

- 1Password app integration が一時的に遅い、locked、未認証、または応答待ちになるだけで
  `chezmoi apply` 全体が失敗しやすい。
- shell や GUI tool の secret は、起動時に毎回読むのではなく、必要なコマンド実行時または deploy script 実行時に取得し、
  失敗時は warning / fallback で続行できる方が扱いやすい。

使い分け:

- `onepasswordRead`: secret が取れないなら template 生成を失敗させたい場合だけ使う。
- `op read`: deploy script など、値を 1 つずつ runtime 取得したい場合に使う。
- `op inject`: `op://...` を含む env template を shell の process 環境へ展開したい場合に使う。
- `op run --env-file`: shell / GUI launcher の子プロセスへ明示的に env をまとめて渡したい場合に使う。既定起動には使わない。

### Chezmoi 公式 1Password 連携

参照:

- [Password Manager Integration](https://chezmoi.io/user-guide/password-managers/)
- [1Password](https://chezmoi.io/user-guide/password-managers/1password/)
- [`onepasswordRead`](https://chezmoi.io/reference/templates/1password-functions/onepasswordRead/)
- [`onepasswordDetailsFields`](https://chezmoi.io/reference/templates/1password-functions/onepasswordDetailsFields/)
- [1Password template functions](https://chezmoi.io/reference/templates/1password-functions/onepassword/)

公式の要点:

- `onepasswordRead "op://vault/item/field"` は `op read --no-newline op://vault/item/field` 相当。
- `onepasswordRead` の第 2 引数に account を渡すと、`op` に `--account` が渡る。
- `onepasswordDetailsFields` は item の structured fields を map として扱う用途で、同じ item への呼び出しは cache される。
- `onePassword.command` で使う `op` command、`onePassword.args` で追加引数を設定できる。
- 有効な session が無い場合、通常は対話的な sign-in に進む。

この repo の判断:

- 複数 account 環境では、template 関数を使う場合も account を明示する。
- Windows で template 関数に寄せる場合は、`onePassword.args` で `--cache=false` を渡す案を検討する。
- ただし通常の `.tmpl` は `onepasswordRead` へ戻さず、runtime の `op read` / `op inject` に寄せる。
  `chezmoi apply` 全体を secret manager の一時的な応答待ちに巻き込まないため。

## 今回の調査で分かったこと

Windows の `op` は global flag `--cache` の既定値が true だが、CLI help では
Windows で caching は使えないとされている。実測では、Windows 上の非対話実行で
`op inject` / `op read` / `op vault list` を既定 cache のまま呼ぶと、
1Password app integration の認可自体は成功していても、cache daemon 接続の後で
timeout することがあった。

そのため Windows で `op` を非対話・timeout 付きに呼ぶ箇所では、原則として
`--cache=false` を付ける。WSL から Windows の `op.exe` を使う場合も同じ。

Linux / macOS の native `op` は UNIX-like として cache が使えるため、Windows の
`--cache=false` ルールをそのまま一般化しない。

## SSH / Git 連携

1Password SSH Agent と `op-ssh-sign` の OS 別パスは OS 別ドキュメントに置く。

- Windows: [windows.md](./windows.md)
- WSL: [wsl.md](./wsl.md)
- Linux: [linux.md](./linux.md)
- macOS: [macos.md](./macos.md)
