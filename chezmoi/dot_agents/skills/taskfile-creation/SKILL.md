---
name: taskfile-creation
description: Create and organize Taskfile.yml for go-task/task runner. Use when creating new Taskfile.yml, adding task groups, setting up includes, writing cross-platform tasks (Windows/WSL/Linux/macOS), adding validation or incremental builds, or automating workflows with Taskfile. Follows this repository's conventions for directory layout, includes pattern, cross-platform support, and variable naming.
---

# Taskfile Creation

## Repository Conventions

### Directory Layout

Task groups live under `taskfiles/<group-name>/Taskfile.yml` (git submodule) and are included from the root `Taskfile.yml`:

```yaml
includes:
  <group>:
    taskfile: taskfiles/<group-name>/Taskfile.yml
    dir: taskfiles/<group-name>
```

Always set `dir` alongside `taskfile`. Invocation: `task <group>:<task-name>`

### Common Variables

Root-level vars:

```yaml
vars:
  DISTRO: NixOS
  DOTFILES_PATH: ~/.dotfiles
```

Included Taskfiles do NOT inherit parent vars. Redeclare needed vars in each sub-Taskfile.

### Naming Conventions

| Element         | Convention                    | Example                    |
| --------------- | ----------------------------- | -------------------------- |
| Group directory | `snake_case` or `kebab-case`  | `taskfiles/github_runner/` |
| Task name       | `kebab-case`                  | `dry-run`, `sync-agents`   |
| WSL variant     | `<name>:wsl` suffix           | `install:wsl`              |
| Internal task   | `_` prefix + `internal: true` | `_validate`, `_run`        |

### Essential Rules

- Every public task MUST have `desc` (shown in `task --list`)
- Use `preconditions` for required tools or CLI arguments
- Use `platforms` for OS-specific control (never template conditionals)
- Use `deps` for parallel prerequisites, `cmds` with `task:` for sequential steps
- Set `interactive: true` on tasks requiring user input

## References

Read the appropriate reference when working with specific patterns.

| When                                                    | Read                                                    |
| ------------------------------------------------------- | ------------------------------------------------------- |
| Taskfile v3 syntax (vars, cmds, deps, includes, loops)  | [taskfile-syntax.md](references/taskfile-syntax.md)     |
| OS-specific control (`platforms`, Windows+WSL patterns) | [cross-platform.md](references/cross-platform.md)       |
| Concrete patterns from this repository                  | [existing-patterns.md](references/existing-patterns.md) |
