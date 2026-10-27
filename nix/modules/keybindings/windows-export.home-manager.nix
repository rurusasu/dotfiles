{ lib, ... }:
{
  options.dotfiles.keybindings.fromWindowsExport = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Read WSL application keys from the chezmoi deployed Nix JSON export.";
  };
}
