# Taskfile v3 Syntax Reference

Taskfile v3 の構文リファレンス。

## File Structure

OK:

```yaml
version: "3"

includes:
  <namespace>:
    taskfile: <path>
    dir: <path>

vars:
  KEY: value
  DYNAMIC: { sh: "echo hello" }

env:
  ENV_VAR: value

tasks:
  <task-name>: ...
```

NG:

```yaml
version: "2"

tasks:
  <task-name>: ...
```

Why: v2 は非推奨。`version: "3"` を必ず指定する。

Source: <https://taskfile.dev/usage/#getting-started>

## Task Properties

OK:

```yaml
tasks:
  example:
    desc: Short description (shown in task --list)
    summary: |
      Longer description shown with task --summary example
    aliases: [ex, e]
    cmds:
      - echo "hello"
    deps: [other-task]
    dir: ./subdir
    env:
      FOO: bar
    vars:
      LOCAL_VAR: value
    silent: true
    interactive: true
    internal: true
    platforms: [linux, darwin, windows]
    requires:
      vars: [VAR1, VAR2]
    preconditions:
      - sh: test -f file.txt
        msg: "file.txt not found"
    sources:
      - src/**/*.go
    generates:
      - bin/app
    status:
      - test -f bin/app
    run: once
    ignore_error: true
    label: "build-{{.ARCH}}"
```

NG:

```yaml
tasks:
  example:
    cmds:
      - echo "hello"
```

Why: `desc` がないと `task --list` に表示されない。公開タスクには必ず `desc` を付ける。`internal: true` の場合は省略可。

Source: <https://taskfile.dev/reference/schema/#task>

## Commands

OK:

```yaml
cmds:
  # Simple command
  - echo "hello"

  # Command with options
  - cmd: echo "hello"
    silent: true
    ignore_error: true
    platforms: [linux]

  # Multi-line shell block
  - cmd: |
      if [ -f config.yml ]; then
        echo "found"
      fi

  # Call another task
  - task: other-task
    vars:
      KEY: value

  # Deferred command (runs at end even on failure)
  - defer: rm -f tmpfile
```

NG:

```yaml
cmds:
  - |
    echo "step1"
    echo "step2"
    echo "step3"
```

Why: 全コマンドを 1 つのシェルブロックに詰め込むと、個別タスクとして再利用・テストできない。`task:` 呼び出しやコマンド分割を検討すべき。

Source: <https://taskfile.dev/reference/schema/#command>

## Variables

OK:

```yaml
vars:
  # Static
  NAME: value

  # Dynamic (shell)
  GIT_SHA: { sh: "git rev-parse --short HEAD" }

  # CLI arguments: task example -- args here
  # Available as {{.CLI_ARGS}}

  # Built-in
  # {{.ROOT_DIR}}     - root Taskfile directory
  # {{.TASKFILE_DIR}} - current Taskfile directory
  # {{.TASK}}         - current task name
  # {{OS}}            - runtime.GOOS (linux, darwin, windows)
  # {{ARCH}}          - runtime.GOARCH (amd64, arm64)
```

NG:

```yaml
vars:
  IS_WINDOWS: '{{if eq OS "windows"}}true{{else}}false{{end}}'
```

Why: OS 分岐にはテンプレート条件分岐ではなく `platforms` 属性を使う。詳細は [cross-platform.md](cross-platform.md) を参照。

Source: <https://taskfile.dev/usage/#variables>

## Template Functions

Go template syntax with sprig functions:

OK:

```yaml
vars:
  NAME: '{{.CLI_ARGS | default "world"}}'
  UPPER: "{{.NAME | upper}}"
```

NG:

```yaml
vars:
  NAME: "{{if .CLI_ARGS}}{{.CLI_ARGS}}{{else}}world{{end}}"
```

Why: sprig の `default` 関数を使う方が簡潔で可読性が高い。

Source: <https://taskfile.dev/usage/#variables>

## Includes

OK:

```yaml
includes:
  # With directory (recommended)
  build:
    taskfile: ./build/Taskfile.yml
    dir: ./build

  # Optional (no error if missing)
  optional:
    taskfile: ./optional/Taskfile.yml
    optional: true

  # Flattened (no namespace prefix)
  flat:
    taskfile: ./other/Taskfile.yml
    flatten: true
```

NG:

```yaml
includes:
  build:
    taskfile: ./build/Taskfile.yml
```

Why: `dir` を省略するとスクリプトの相対パスが壊れる。`taskfile` と `dir` は常にセットで指定する。

Source: <https://taskfile.dev/usage/#including-other-taskfiles>

**Important:** Included Taskfiles do NOT inherit parent vars. Redeclare needed vars in each sub-Taskfile.

## Dependencies vs Commands

OK:

```yaml
tasks:
  # deps run in parallel, before cmds
  release:
    deps: [lint, test]
    cmds:
      - task: build
      - task: deploy

  # deps with vars
  compile:
    deps:
      - task: setup
        vars: { ENV: prod }
```

NG:

```yaml
tasks:
  release:
    cmds:
      - task: lint
      - task: test
      - task: build
      - task: deploy
```

Why: `lint` と `test` は独立しているため `deps` で並列実行できる。`cmds` はすべて直列実行。

Source: <https://taskfile.dev/usage/#task-dependencies>

## Preconditions

OK:

```yaml
tasks:
  deploy:
    preconditions:
      - sh: command -v kubectl
        msg: "kubectl is required"
      - sh: test -n "{{.CLI_ARGS}}"
        msg: "Usage: task deploy -- <env>"
      - sh: test -f config.yml
        msg: "config.yml not found"
```

NG:

```yaml
tasks:
  deploy:
    cmds:
      - |
        if ! command -v kubectl; then echo "kubectl required"; exit 1; fi
        kubectl apply -f config.yml
```

Why: `preconditions` は deps と cmds の前に評価され、失敗時のメッセージが統一される。

Source: <https://taskfile.dev/usage/#preconditions>

## Incremental Builds

OK:

```yaml
tasks:
  build:
    sources:
      - src/**/*.go
      - go.mod
    generates:
      - bin/app
    cmds:
      - go build -o bin/app .

  check:
    status:
      - test -f .initialized
    cmds:
      - ./initialize.sh
```

NG:

```yaml
tasks:
  build:
    cmds:
      - go build -o bin/app .
```

Why: `sources`/`generates` なしだと毎回ビルドが走る。変更がなければスキップされるべき。

Source: <https://taskfile.dev/usage/#reduce-unnecessary-work>

## Platform Filtering

OS 分岐は `platforms` で制御する。詳細は [cross-platform.md](cross-platform.md) を参照。

OK:

```yaml
tasks:
  build:
    cmds:
      - cmd: make build
        platforms: [linux, darwin]
      - cmd: nmake build
        platforms: [windows]
```

NG:

```yaml
tasks:
  build:
    cmds:
      - '{{if eq OS "windows"}}nmake build{{else}}make build{{end}}'
```

Why: `platforms` は Taskfile 組み込み機能。テンプレート分岐は可読性が低い。

Source: <https://taskfile.dev/usage/#platforms>

## Looping

OK:

```yaml
tasks:
  lint:
    cmds:
      - for: [src, tests, scripts]
        cmd: echo "Linting {{.ITEM}}"

      - for: { var: FILES, split: "," }
        cmd: echo "{{.ITEM}}"

      - for:
          matrix:
            OS: [linux, darwin]
            ARCH: [amd64, arm64]
        cmd: echo "{{.ITEM.OS}}-{{.ITEM.ARCH}}"
```

NG:

```yaml
tasks:
  lint:
    cmds:
      - echo "Linting src"
      - echo "Linting tests"
      - echo "Linting scripts"
```

Why: `for` を使えばリスト変更時にコマンドの追加・削除が不要。

Source: <https://taskfile.dev/usage/#looping-over-values>
