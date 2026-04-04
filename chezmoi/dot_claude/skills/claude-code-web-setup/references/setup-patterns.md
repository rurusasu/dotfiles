# Setup Script Patterns

## Cloud Environment Setup Script (claude.ai/code UI)

Locates and runs the repo's `setup.sh` without hardcoded paths:

```bash
#!/bin/bash
REPO=$(find /home -maxdepth 3 -name setup.sh -path "*<repo-name>*" 2>/dev/null | head -1) && cd "$(dirname "$REPO")" && bash setup.sh
```

### Why This Pattern

| Approach                                | Result                                                 |
| --------------------------------------- | ------------------------------------------------------ |
| `bash setup.sh`                         | FAIL — CWD is not repo root                            |
| `cd $HOME/<repo> && bash setup.sh`      | FAIL — `$HOME` = `/root/`, repo is under `/home/user/` |
| `cd /home/user/<repo> && bash setup.sh` | Works but hardcoded                                    |
| `find /home ... && bash setup.sh`       | Works, no hardcode                                     |

## Repository's `setup.sh`

Use `${BASH_SOURCE[0]}` for reliable self-location. See `templates/setup.sh.template`.

Key rules:

- Always `set -e`
- Use `BASH_SOURCE[0]` not `$0`
- Check directory existence before `cd`
- Log repo root for debugging
