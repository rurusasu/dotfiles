# AGENTS

Purpose: Home Manager fzf configuration.
Expected contents:
- default.nix: enables fzf and shell integrations with preferred UI options.
Notes:
- Uses fd for file/directory search
- fd settings (ignores, extraOptions) managed in programs.fd
Keybindings:
- Ctrl+T: File search (insert selected file path)
- Ctrl+R: Command history search
- Alt+C: Subdirectory search (cd to selected)
