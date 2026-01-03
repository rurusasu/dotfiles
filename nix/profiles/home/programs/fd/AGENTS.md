# AGENTS

Purpose: Home Manager fd configuration.
Expected contents:
- default.nix: fd configuration using programs.fd module.
Notes:
- Fast file finder alternative to find command
- Respects .gitignore by default
- hidden = true to include hidden files
- ignores written to ~/.config/fd/ignore
extraOptions:
- --follow: symlink traversal
- --max-results=1000: limit search results
- --max-depth=5: limit search depth
Global ignores:
- .git/, node_modules/, target/, __pycache__/, .cache/
- .nix-profile/, .local/share/, .npm/, .cargo/
