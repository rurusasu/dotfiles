# Shared keybindings configuration for all terminal emulators
# Note: Windows Terminal doesn't support Leader key natively,
# so it uses direct key combinations instead.
{ leader }:
let
  # Convert leader mods to Windows Terminal format (lowercase)
  leaderModsLower =
    builtins.replaceStrings [ "CTRL" "SHIFT" "ALT" "WIN" "|" ] [ "ctrl" "shift" "alt" "win" "+" ]
      leader.mods;
  leaderKeyLower = builtins.replaceStrings [ "Space" ] [ "space" ] leader.key;

  # Windows Terminal leader key combination (e.g., "ctrl+space")
  wtLeaderCombo = "${leaderModsLower}+${leaderKeyLower}";
in
{
  # Shared leader configuration
  inherit leader;

  # Windows Terminal keybindings
  # Note: WT doesn't have Leader key, so we use the leader combo as prefix
  # where possible, or use alternative bindings
  windowsTerminal = {
    # Actions (command definitions)
    actions = [
      {
        command = {
          action = "copy";
          singleLine = false;
        };
        id = "User.copy";
      }
      {
        command = "paste";
        id = "User.paste";
      }
      # Pane split
      {
        command = {
          action = "splitPane";
          split = "right";
          splitMode = "duplicate";
        };
        id = "User.splitPane.horizontal";
      }
      {
        command = {
          action = "splitPane";
          split = "down";
          splitMode = "duplicate";
        };
        id = "User.splitPane.vertical";
      }
      {
        command = "closePane";
        id = "User.closePane";
      }
      {
        command = "togglePaneZoom";
        id = "User.togglePaneZoom";
      }
      {
        command = "toggleFullscreen";
        id = "User.toggleFullscreen";
      }
      {
        command = "find";
        id = "User.find";
      }
      {
        command = "nextTab";
        id = "User.nextTab";
      }
      {
        command = "prevTab";
        id = "User.prevTab";
      }
      # Pane navigation
      {
        command = {
          action = "moveFocus";
          direction = "left";
        };
        id = "User.moveFocus.left";
      }
      {
        command = {
          action = "moveFocus";
          direction = "right";
        };
        id = "User.moveFocus.right";
      }
      {
        command = {
          action = "moveFocus";
          direction = "up";
        };
        id = "User.moveFocus.up";
      }
      {
        command = {
          action = "moveFocus";
          direction = "down";
        };
        id = "User.moveFocus.down";
      }
      # Unbind Alt+C and Alt+Z for fzf
      {
        command = "unbound";
        keys = "alt+c";
      }
      {
        command = "unbound";
        keys = "alt+z";
      }
    ];

    # Keybindings
    # Matches WezTerm keybindings:
    # - Pane split/close/zoom: Ctrl+Alt+H/V/X/W
    # - Pane navigation: Ctrl+Shift+H/J/K/L (Vim-style)
    keybindings = [
      {
        id = "User.copy";
        keys = "ctrl+c";
      }
      {
        id = "User.paste";
        keys = "ctrl+v";
      }
      {
        id = "User.find";
        keys = "ctrl+shift+f";
      }
      # Pane split/close (Ctrl+Alt to match WezTerm)
      {
        id = "User.splitPane.horizontal";
        keys = "ctrl+alt+h";
      }
      {
        id = "User.splitPane.vertical";
        keys = "ctrl+alt+v";
      }
      {
        id = "User.closePane";
        keys = "ctrl+alt+x";
      }
      {
        id = "User.togglePaneZoom";
        keys = "ctrl+alt+w";
      }
      # Pane navigation (Ctrl+Shift + Vim keys to match WezTerm)
      {
        id = "User.moveFocus.left";
        keys = "ctrl+shift+h";
      }
      {
        id = "User.moveFocus.right";
        keys = "ctrl+shift+l";
      }
      {
        id = "User.moveFocus.up";
        keys = "ctrl+shift+k";
      }
      {
        id = "User.moveFocus.down";
        keys = "ctrl+shift+j";
      }
      # Tab navigation
      {
        id = "User.nextTab";
        keys = "ctrl+tab";
      }
      {
        id = "User.prevTab";
        keys = "ctrl+shift+tab";
      }
      # Fullscreen
      {
        id = "User.toggleFullscreen";
        keys = "f11";
      }
    ];
  };

  # WezTerm keybindings (reference for documentation)
  wezterm = {
    leader = {
      key = leader.key;
      mods = leader.mods;
      timeout = leader.timeout;
    };
    # Pane operations use Ctrl+Alt
    pane = {
      splitHorizontal = "CTRL+ALT + h";
      splitVertical = "CTRL+ALT + v";
      close = "CTRL+ALT + x";
      zoom = "CTRL+ALT + w";
    };
    # Navigation uses Ctrl+Shift + Vim keys
    navigation = {
      left = "CTRL+SHIFT + h";
      down = "CTRL+SHIFT + j";
      up = "CTRL+SHIFT + k";
      right = "CTRL+SHIFT + l";
    };
    # Other
    fullscreen = "F11";
  };
}
