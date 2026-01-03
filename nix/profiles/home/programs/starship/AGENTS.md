# AGENTS

Purpose: Home Manager starship configuration.
Expected contents:
- default.nix: starship prompt configuration using programs.starship module.
Notes:
- Fast, customizable cross-shell prompt
- Bash and Zsh integration enabled
- Prompt format: $os $username@$hostname $memory_usage $directory $git_branch $git_status $nix_shell $character
- Example: ` nixos@nixos 1.2GiB ~/dotfiles  main >`
