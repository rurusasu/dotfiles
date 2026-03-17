#!/usr/bin/env bash
echo "=== nix profile ==="
nix profile list 2>&1 | head -10

echo ""
echo "=== nixos-rebuild packages ==="
nix-env -q 2>&1 | head -10

echo ""
echo "=== tool check ==="
for t in fzf eza zoxide rg fd starship git gh nvim task pnpm claude gemini uv zsh pwsh; do
  path=$(command -v "$t" 2>/dev/null)
  if [ -n "$path" ]; then
    ver=$("$t" --version 2>/dev/null | head -1)
    printf "OK   %-12s %s\n" "$t" "$ver"
  else
    printf "MISS %-12s (not found)\n" "$t"
  fi
done
