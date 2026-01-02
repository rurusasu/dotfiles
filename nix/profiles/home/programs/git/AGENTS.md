# AGENTS

Purpose: Home Manager git configuration.
Expected contents:
- default.nix: git configuration using programs.git module.
Notes:
- User: Kohei Miki <rurusasu@gmail.com>
- SSH signing enabled with ~/.ssh/signing_key.pub
- GitHub credential helper via gh CLI
- safe.directory = "*" for WSL cross-filesystem access
