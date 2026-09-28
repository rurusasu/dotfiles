# Windows has no Nix activation; export user artifacts for chezmoi transport.
{ lib }:
let
  rendered = import ../../home/keybindings/glazewm.nix {
    inherit lib;
    commands = import ../../home/keybindings/glazewm-commands.nix { inherit lib; };
  };
in
rendered
// {
  enable = true;
  artifacts = {
    "dot_glzr/glazewm/config.json" = builtins.toJSON rendered.config + "\n";
    "dot_glzr/glazewm/actions.ps1" = builtins.readFile ../../home/keybindings/windows-actions.ps1;
    "dot_glzr/glazewm/start-glazewm.ps1" = builtins.readFile ./start-glazewm.ps1;
    "dot_glzr/glazewm/keybindings.txt" =
      lib.concatMapStringsSep "\n" (
        binding: "${lib.concatStringsSep "+" (binding.modifiers ++ [ binding.key ])}: ${binding.action}"
      ) rendered.supported
      + "\n\nUnsupported/native:\n"
      + lib.concatMapStringsSep "\n" (
        binding: "${binding.action}: ${binding.reason}"
      ) rendered.unsupported
      + "\n";
  };
}
