#!/usr/bin/env bash
#
# Creates CLAUDE.md symlinks pointing to AGENTS.md in all directories.
#
# Usage:
#   ./new-claude-md-symlinks.sh          # Create symlinks
#   ./new-claude-md-symlinks.sh --dry-run # Show what would be done

set -euo pipefail

DRY_RUN=false
if [[ ${1:-} == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Get repository root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$(dirname "$0")")")"

echo "Repository root: $REPO_ROOT"

created=0
skipped=0
errors=0

# Find all AGENTS.md files
while IFS= read -r -d '' agents_file; do
  dir="$(dirname "$agents_file")"
  claude_md="$dir/CLAUDE.md"

  # Check if CLAUDE.md already exists
  if [[ -e $claude_md ]]; then
    if [[ -L $claude_md ]]; then
      # It's a symlink, remove and recreate
      if [[ $DRY_RUN == "false" ]]; then
        rm -f "$claude_md"
      fi
      echo "  Replacing existing symlink: $claude_md"
    else
      # It's a regular file, skip
      echo "  Skipping (regular file exists): $claude_md"
      ((skipped++)) || true
      continue
    fi
  fi

  # Create symlink
  if [[ $DRY_RUN == "true" ]]; then
    echo "  Would create: $claude_md -> AGENTS.md"
    ((created++)) || true
  else
    if ln -s "AGENTS.md" "$claude_md" 2>/dev/null; then
      echo "  Created: $claude_md -> AGENTS.md"
      ((created++)) || true
    else
      echo "  Failed: $claude_md"
      ((errors++)) || true
    fi
  fi
done < <(find "$REPO_ROOT" -name "AGENTS.md" -type f -print0)

echo ""
echo "Summary:"
echo "  Created: $created"
echo "  Skipped: $skipped"
echo "  Errors:  $errors"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
