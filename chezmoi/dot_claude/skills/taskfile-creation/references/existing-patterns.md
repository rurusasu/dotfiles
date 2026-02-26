# Existing Taskfile Patterns in This Repository

このリポジトリで使われている Taskfile パターン集。

## Includes (git submodule)

各タスクグループは `taskfiles/` (git submodule) 配下の Taskfile に分離。

OK:

```yaml
includes:
  runner:
    taskfile: taskfiles/github_runner/Taskfile.yml
    dir: taskfiles/github_runner
  skills:
    taskfile: taskfiles/skills/Taskfile.yml
    dir: taskfiles/skills
  lint:
    taskfile: taskfiles/lint/Taskfile.yml
    dir: taskfiles/lint
```

NG:

```yaml
includes:
  lint:
    taskfile: taskfiles/lint/Taskfile.yml
    # dir を省略
```

Why: `dir` を省略するとルート Taskfile のディレクトリが作業ディレクトリになり、相対パスのスクリプト参照が壊れる。

Source: <https://taskfile.dev/usage/#including-other-taskfiles>

## WSL Wrapper with `platforms`

`taskfiles/lint/Taskfile.yml` の内部ヘルパー。`platforms` で Windows/Linux を分岐。

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

  shellcheck:
    desc: Run shellcheck (shell script linting)
    cmds:
      - task: _run
        vars: { LINTER: shellcheck }
```

NG:

```yaml
vars:
  IS_WINDOWS: '{{if eq OS "windows"}}true{{else}}false{{end}}'

tasks:
  _run:
    cmds:
      - '{{if eq .IS_WINDOWS "true"}}wsl -d ... "{{else}}./run-lint.sh ...{{end}}'
```

Why: テンプレート条件分岐ではなく `platforms` を使う。詳細は [cross-platform.md](cross-platform.md) を参照。

Source: <https://taskfile.dev/usage/#platforms>

## Validation with Internal deps

`taskfiles/gcloud/Taskfile.yml` でツール存在チェックを `preconditions` + `deps` で実装。

OK:

```yaml
tasks:
  _validate:
    internal: true
    preconditions:
      - sh: command -v gcloud
        msg: "gcloud CLI is not installed"

  adc:
    desc: Google Cloud ADC authentication
    interactive: true
    deps: [_validate]
    cmds:
      - cmd: |
          if ! gcloud auth print-access-token >/dev/null 2>&1; then
            gcloud auth login
          fi
```

NG:

```yaml
tasks:
  adc:
    cmds:
      - |
        if ! command -v gcloud; then
          echo "gcloud not found"; exit 1
        fi
        gcloud auth login
```

Why: `preconditions` を使うとエラーメッセージが統一され、`deps` で再利用可能。コマンド内での手動チェックは冗長。

Source: <https://taskfile.dev/usage/#preconditions>

## CLI_ARGS Passthrough

`taskfiles/skills/Taskfile.yml` でユーザー引数をスクリプトに渡す。

OK:

```yaml
tasks:
  install:
    preconditions:
      - sh: test -n "{{.CLI_ARGS}}"
        msg: |
          Error: Repository is required.
          Usage: task skills:install -- <repo> [--skill <skill>]
    cmds:
      - pwsh -NoProfile -ExecutionPolicy Bypass -File ./Manage-Skills.ps1 -Action Install {{.CLI_ARGS}}
```

NG:

```yaml
tasks:
  install:
    cmds:
      - pwsh -NoProfile -ExecutionPolicy Bypass -File ./Manage-Skills.ps1 -Action Install {{.CLI_ARGS}}
```

Why: `preconditions` なしだと空引数でスクリプトがエラーになり、ユーザーに使い方が伝わらない。

Source: <https://taskfile.dev/usage/#cli-arguments>

## Systemd Service Management

`taskfiles/github_runner/Taskfile.yml` で systemctl コマンドをラップ。

OK:

```yaml
vars:
  SERVICE_NAME: github-actions-runner.service

tasks:
  status:
    desc: Show runner systemd status (WSL)
    cmds:
      - >
        wsl -d {{.DISTRO}} -- bash -lc
        "sudo systemctl status {{.SERVICE_NAME}} --no-pager || true"

  restart:
    desc: Restart runner service (WSL)
    cmds:
      - >
        wsl -d {{.DISTRO}} -- bash -lc
        "sudo systemctl restart {{.SERVICE_NAME}}"
```

NG:

```yaml
tasks:
  status:
    cmds:
      - wsl -d NixOS -- bash -lc "sudo systemctl status github-actions-runner.service --no-pager || true"

  restart:
    cmds:
      - wsl -d NixOS -- bash -lc "sudo systemctl restart github-actions-runner.service"
```

Why: サービス名やディストロ名が重複。`vars` で変数化して一元管理すべき。

Source: <https://taskfile.dev/usage/#variables>

## Default Task as Help

`taskfiles/skills/Taskfile.yml` で `default` タスクに使い方を表示。

OK:

```yaml
tasks:
  default:
    desc: Show available commands
    silent: true
    cmds:
      - |
        pwsh -NoProfile -Command "
        Write-Host 'Available commands:'
        Write-Host '  task skills:install -- <repo>'
        Write-Host '  task skills:remove -- <name>'
        "
```

NG:

```yaml
tasks:
  default:
    cmds:
      - task --list
```

Why: `task --list` は全タスク一覧を表示するが、名前空間付きで呼ばれた場合の使い方は伝わらない。カスタムヘルプの方がユーザーフレンドリー。

Source: <https://taskfile.dev/usage/#task-aliases>

## Git Operations via WSL

Root `Taskfile.yml` でタスクチェーンを使ったコミットワークフロー。

OK:

```yaml
tasks:
  commit:
    desc: Format, lint, test, and commit
    cmds:
      - task: fmt
      - task: lint:all
      - task: pre-commit
      - task: test:powershell
      - wsl -d {{.DISTRO}} -- bash -lc "cd {{.DOTFILES_PATH}} && git add -A && nix develop --command cz commit --signoff"

  commit:push:
    desc: Commit and push
    cmds:
      - task: commit
      - task: lint:commitlint
      - wsl -d {{.DISTRO}} -- bash -lc "cd {{.DOTFILES_PATH}} && git push"
```

NG:

```yaml
tasks:
  commit:
    cmds:
      - wsl -d NixOS -- bash -lc "cd ~/.dotfiles && nix fmt && nix develop --command pre-commit run --all-files && git add -A && nix develop --command cz commit --signoff"
```

Why: 1 コマンドに全処理を詰め込むと、途中で失敗した場合のデバッグが困難。`task:` で分割すれば個別実行・再実行が可能。

Source: <https://taskfile.dev/usage/#calling-another-task>
