# AGENTS

Purpose
Purpose: Home Manager entrypoints per host.
Expected contents:
- <host>/default.nix: imports user file + shared home profile(s).
- users/: per-user home definitions.
Notes:
- Keep host-specific HM entrypoints minimal; compose via profiles.

