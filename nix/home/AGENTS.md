# AGENTS

Purpose: Home Manager entrypoints per host.
Expected contents:
- <host>/default.nix: defines username/homeDirectory and imports profiles.
Notes:
- Keep host-specific HM entrypoints minimal; compose via profiles.
- User info is defined directly in each host's default.nix.
