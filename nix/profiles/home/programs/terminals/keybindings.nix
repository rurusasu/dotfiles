# Shared keybindings configuration for all terminal emulators
# Note: Windows Terminal doesn't support Leader key natively,
# so it uses direct key combinations instead.
{ leader }:
let
  # Convert leader mods to Windows Terminal format (lowercase)
  leaderModsLower = builtins.replaceStrings [ "CTRL" "SHIFT" "ALT" "WIN" "|" ] [ "ctrl" "shift" "alt" "win" "+" ] leader.mods;
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
        command = { action = "copy"; singleLine = false; };
        id = "User.copy";
      }
      { command = "paste"; id = "User.paste"; }
      # Pane split
      {
        command = { action = "splitPane"; split = "right"; splitMode = "duplicate"; };
        id = "User.splitPane.horizontal";
      }
      {
        command = { action = "splitPane"; split = "down"; splitMode = "duplicate"; };
        id = "User.splitPane.vertical";
      }
      { command = "closePane"; id = "User.closePane"; }
      { command = "find"; id = "User.find"; }
      { command = "nextTab"; id = "User.nextTab"; }
      { command = "prevTab"; id = "User.prevTab"; }
      # Pane navigation
      {
        command = { action = "moveFocus"; direction = "left"; };
        id = "User.moveFocus.left";
      }
      {
        command = { action = "moveFocus"; direction = "right"; };
        id = "User.moveFocus.right";
      }
      {
        command = { action = "moveFocus"; direction = "up"; };
        id = "User.moveFocus.up";
      }
      {
        command = { action = "moveFocus"; direction = "down"; };
        id = "User.moveFocus.down";
      }
      # Unbind Alt+C and Alt+Z for fzf
      { command = "unbound"; keys = "alt+c"; }
      { command = "unbound"; keys = "alt+z"; }
    ];

    # Keybindings
    # Matches WezTerm where possible:
    # - Pane split: Ctrl+Shift+H/V (horizontal/vertical) - since WT has no Leader
    # - Pane close: Ctrl+Shift+X
    # - Pane navigation: Ctrl+Shift+H/J/K/L (Vim-style)
    keybindings = [
      { id = "User.copy"; keys = "ctrl+c"; }
      { id = "User.paste"; keys = "ctrl+v"; }
      { id = "User.find"; keys = "ctrl+shift+f"; }
      # Pane split (Ctrl+Shift+H/V to match WezTerm's Leader+h/v concept)
      { id = "User.splitPane.horizontal"; keys = "ctrl+shift+h"; }
      { id = "User.splitPane.vertical"; keys = "ctrl+shift+v"; }
      { id = "User.closePane"; keys = "ctrl+shift+x"; }
      # Pane navigation (Ctrl+Alt + Vim keys)
      { id = "User.moveFocus.left"; keys = "ctrl+alt+h"; }
      { id = "User.moveFocus.right"; keys = "ctrl+alt+l"; }
      { id = "User.moveFocus.up"; keys = "ctrl+alt+k"; }
      { id = "User.moveFocus.down"; keys = "ctrl+alt+j"; }
      # Tab navigation
      { id = "User.nextTab"; keys = "ctrl+tab"; }
      { id = "User.prevTab"; keys = "ctrl+shift+tab"; }
    ];
  };

  # WezTerm keybindings (reference for documentation)
  wezterm = {
    leader = {
      key = leader.key;
      mods = leader.mods;
      timeout = leader.timeout;
    };
    # Pane operations use LEADER prefix
    pane = {
      splitHorizontal = "LEADER + h";
      splitVertical = "LEADER + v";
      close = "LEADER + x";
    };
    # Navigation uses Ctrl+Shift + Vim keys
    navigation = {
      left = "CTRL+SHIFT + h";
      down = "CTRL+SHIFT + j";
      up = "CTRL+SHIFT + k";
      right = "CTRL+SHIFT + l";
    };
  };
}
