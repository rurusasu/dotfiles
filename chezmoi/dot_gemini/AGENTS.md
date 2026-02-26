# Gemini CLI Configuration

This directory contains Google Gemini CLI configuration.

## Files

- `settings.json` - Gemini CLI settings

## Deployment

Deployed to `~/.gemini/` via chezmoi on all platforms.

## Installation

| Platform | Method | Config                                                         |
| -------- | ------ | -------------------------------------------------------------- |
| NixOS    | Nix    | [`nix/core/cli.nix`](../../nix/core/cli.nix)                   |
| Windows  | npm    | [`windows/npm/packages.json`](../../windows/npm/packages.json) |
