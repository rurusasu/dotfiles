{
  config,
  lib,
  pkgs,
  ...
}:
let
  appearance = import ../appearance.nix;
in
{
  config = lib.mkIf config.programs.alacritty.enable {
    programs.alacritty = {
      inherit (appearance) theme;
      settings = {
        font = {
          inherit (appearance) font_size;
          normal.family = appearance.font_family;
        };
        keyboard.bindings = [
          # Shift+Enter inserts a newline for multi-line AI prompts.
          {
            key = "Return";
            mods = "Shift";
            chars = "\n";
          }
          # The desktop keymap owns Command-based shortcuts on macOS.
          {
            key = "0";
            mods = "Control | Shift";
            action = "ResetFontSize";
          }
          {
            key = "+";
            mods = "Control | Shift";
            action = "IncreaseFontSize";
          }
          {
            key = "-";
            mods = "Control | Shift";
            action = "DecreaseFontSize";
          }
        ];
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        # Send ESC-prefixed Alt sequences for fzf, zoxide and PSReadLine.
        window.option_as_alt = "Both";
      };
    };

    # Alacritty ships terminfo separately from the terminal binary.
    home.packages = lib.optional (
      config.programs.alacritty.package != null && config.programs.alacritty.package ? terminfo
    ) config.programs.alacritty.package.terminfo;
  };
}
