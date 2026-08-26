# Cross-Platform Task Control

OS ごとに処理が変わる場合は、必ず Taskfile の `platforms` 属性で制御する。

## cmd レベルの `platforms`（推奨）

同一タスク内で OS ごとにコマンドを切り替え。

OK:

```yaml
tasks:
  _run:
    internal: true
    vars:
      LINTER: "{{.LINTER}}"
    cmds:
      - cmd: wsl -d {{.DISTRO}} -- bash -lc "cd {{.DOTFILES_PATH}} && nix develop --command ./taskfiles/lint/run-lint.sh {{.LINTER}}"
        platforms: [windows]
      - cmd: |
          if command -v nix >/dev/null 2>&1; then
            nix develop --command ./run-lint.sh {{.LINTER}}
          else
            ./run-lint.sh {{.LINTER}}
          fi
        platforms: [linux, darwin]
```

NG:

```yaml
vars:
  IS_WINDOWS: '{{if eq OS "windows"}}true{{else}}false{{end}}'

tasks:
  _run:
    cmds:
      - |
        {{if eq .IS_WINDOWS "true"}}wsl -d {{.DISTRO}} -- bash -lc "..."
        {{else}}./run-lint.sh {{.LINTER}}
        {{end}}
```

Why: テンプレート条件分岐は可読性が低く、コマンド全体が文字列結合される。`platforms` は Taskfile 組み込み機能で、該当 OS でのみ cmd が実行される。

Source: <https://taskfile.dev/usage/#platforms>

## task レベルの `platforms`

タスク全体を特定 OS に制限。

OK:

```yaml
tasks:
  install:
    platforms: [linux, darwin]
    cmds:
      - apt-get install -y package

  install-windows:
    platforms: [windows]
    cmds:
      - choco install package
```

NG:

```yaml
tasks:
  install:
    cmds:
      - cmd: apt-get install -y package
        platforms: [linux, darwin]
      - cmd: choco install package
        platforms: [windows]
```

Why: タスク全体が単一 OS 向けなら task レベルの `platforms` の方が意図が明確。cmd レベルは同一タスク内で OS ごとにコマンドが異なる場合に使う。

Source: <https://taskfile.dev/usage/#platforms>

## Windows + WSL デュアルサポート

Windows (PowerShell) と WSL (Bash) で同機能を提供する場合は、`:wsl` サフィックスで明示的に分ける。

OK:

```yaml
tasks:
  sync:
    desc: Install all skills (Windows)
    cmds:
      - pwsh -NoProfile -ExecutionPolicy Bypass -File ./Manage-Skills.ps1 -Action Sync

  sync:wsl:
    desc: Install all skills (via WSL)
    cmds:
      - >
        wsl -d {{.DISTRO}} -- bash -lc
        "cd {{.DOTFILES_PATH}}/taskfiles/skills &&
        ./manage-skills.sh sync"
```

NG:

```yaml
tasks:
  sync:
    cmds:
      - |
        {{if eq .IS_WINDOWS "true"}}pwsh -NoProfile -File ./Manage-Skills.ps1 -Action Sync
        {{else}}./manage-skills.sh sync
        {{end}}
```

Why: ユーザーが明示的に Windows/WSL を選択できる。`task --list` で両方のタスクが表示され、ヘルプとしても機能する。

Source: <https://taskfile.dev/usage/#platforms>

## Available Platform Values

`platforms` に指定可能な値（Go の `runtime.GOOS`）:

| Value     | OS               |
| --------- | ---------------- |
| `windows` | Windows          |
| `linux`   | Linux (WSL 含む) |
| `darwin`  | macOS            |
| `freebsd` | FreeBSD          |

Source: <https://taskfile.dev/reference/schema/#platforms>
