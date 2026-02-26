---
name: codex
description: |
  Consult and review code or wording using Codex CLI (OpenAI).
  Triggers: "codex", "use codex", "ask codex", "code review", "review this", "consult codex", "debug with codex"
  Also triggers on Japanese equivalents: "codexを使って", "codexと相談", "codexに聞いて", "コードレビュー", "レビューして"
  Use cases: (1) wording/message review, (2) code review, (3) design consultation, (4) bug investigation, (5) hard-to-resolve issues
---

# Codex

Skill for running code review and analysis via Codex CLI.

## Command

```bash
codex exec --full-auto --sandbox read-only --cd <project_directory> "<request>"
```

## Prompt Rules

**Important**: Always append the following instruction to the end of every request passed to Codex:

> "No confirmation or questions needed. Provide concrete suggestions, fixes, and code examples proactively."

## Parameters

| Parameter             | Description                          |
| --------------------- | ------------------------------------ |
| `--full-auto`         | Run in fully automatic mode          |
| `--sandbox read-only` | Read-only sandbox (safe analysis)    |
| `--cd <dir>`          | Target project directory             |
| `"<request>"`         | Request content (Japanese supported) |

## Examples

### Code Review

```bash
codex exec --full-auto --sandbox read-only --cd /path/to/project "Review this project's code and point out improvements. No confirmation or questions needed. Provide concrete fixes and code examples proactively."
```

### Bug Investigation

```bash
codex exec --full-auto --sandbox read-only --cd /path/to/project "Investigate the cause of the authentication error. No confirmation or questions needed. Identify the root cause and provide concrete fixes proactively."
```

### Architecture Analysis

```bash
codex exec --full-auto --sandbox read-only --cd /path/to/project "Analyze and explain this project's architecture. No confirmation or questions needed. Provide improvement suggestions proactively."
```

### Refactoring Proposal

```bash
codex exec --full-auto --sandbox read-only --cd /path/to/project "Identify technical debt and propose a refactoring plan. No confirmation or questions needed. Provide concrete code examples proactively."
```

### Design Consultation (UI/UX)

```bash
codex exec --full-auto --sandbox read-only --cd /path/to/project "As a world-class UI designer, evaluate this project's UI from these perspectives: (1) visual hierarchy and typography, (2) spacing rhythm, (3) color palette contrast and accessibility, (4) interaction pattern consistency, (5) cognitive load reduction. No confirmation or questions needed. Provide concrete improvements with code examples proactively."
```

## Execution Steps

1. Receive the request from the user
2. Determine the target project directory (current working directory or user-specified)
3. Compose the prompt and append "No confirmation or questions needed. Provide concrete suggestions proactively."
4. Run Codex with the command format above
5. Report the results to the user
