#!/bin/sh
# Debian resets PATH for login shells used by Task's platform adapters.
export PATH="/opt/ci-tools/bin:/nix/var/nix/profiles/default/bin:$PATH"
