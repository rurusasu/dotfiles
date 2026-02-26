---
name: python-docstring
description: |
  Skill for adding, reviewing, and creating Google-style docstrings for Python code.
  Supports extended format including design decisions, change rationale, and reference links.
  Use for requests like 「docstring を追加して」「docstring をレビューして」「このクラスの docstring を書いて」
  「ドキュメント化して」.
  Automatic validation via pydocstyle is also available.
---

# Python Docstring Skill

Create and review extended docstrings based on Google style, including design decisions, change rationale, and reference links.

## Workflow

### 1. Adding docstrings to existing code

1. Review the entire code and identify missing docstrings
2. Add appropriate docstrings to each element (module, class, method, function)
3. Validate with `scripts/validate_docstring.py`

### 2. Reviewing and fixing docstrings

1. Review existing docstrings
2. Check syntax against [google-style-spec.md](references/google-style-spec.md)
3. Check for design decisions and references against [extended-sections.md](references/extended-sections.md)
4. Point out deficiencies and improvements, and propose fixes

### 3. Creating new code

Write appropriate docstrings simultaneously with code creation.

## Core Principles

- **First line**: Concise imperative form (e.g., `Manage database connections.`)
- **Blank line**: Insert blank line after first line before detailed description
- **Design Decisions**: Document why this implementation was chosen and what decisions were made
- **References**: Include links to referenced documents, Issues, and PRs
- **Language**: Japanese for this skill (can be changed per project)

## Reference Files

| File                                                    | Purpose                                                              |
| ------------------------------------------------------- | -------------------------------------------------------------------- |
| [google-style-spec.md](references/google-style-spec.md) | Standard sections specification (Args, Returns, Raises, etc.)        |
| [extended-sections.md](references/extended-sections.md) | How to write design decisions, change rationale, and reference links |
| [examples.md](references/examples.md)                   | Complete examples for functions, classes, and modules                |

## Validation

```bash
python scripts/validate_docstring.py <target_file.py>
```

Performs basic pydocstyle checks + verifies presence of extended sections.
