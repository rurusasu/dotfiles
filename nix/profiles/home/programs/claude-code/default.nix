{ pkgs, ... }:
{
  home.packages = [
    pkgs.claude-code
    pkgs.codex
  ];

  home.file.".claude/settings.json".source = ../../../../../claude/settings.json;
  home.file.".codex/config.toml".source = ../../../../../codex/config.toml;
}
