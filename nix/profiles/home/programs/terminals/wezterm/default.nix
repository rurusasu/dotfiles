{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.wezterm;
  terminalsCfg = config.myHomeSettings.terminals;

  # Gruvbox Dark colors (Base16 style)
  colors = {
    base00 = "#1d2021"; # Background
    base01 = "#3c3836"; # Lighter background
    base02 = "#504945"; # Selection background
    base03 = "#665c54"; # Comments
    base04 = "#bdae93"; # Dark foreground
    base05 = "#d5c4a1"; # Default foreground
    base06 = "#ebdbb2"; # Light foreground
    base07 = "#fbf1c7"; # Light background
    base08 = "#fb4934"; # Red
    base09 = "#fe8019"; # Orange
    base0A = "#fabd2f"; # Yellow
    base0B = "#b8bb26"; # Green
    base0C = "#8ec07c"; # Cyan
    base0D = "#83a598"; # Blue
    base0E = "#d3869b"; # Purple
    base0F = "#d65d0e"; # Brown
  };

  # Import keybindings (uses shared leader and tab configs)
  keybind = import ./keybind {
    leader = terminalsCfg.leader;
    tabKeys = terminalsCfg.keybindings.tab;
  };
in
{
  options = {
    myHomeSettings.wezterm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable WezTerm terminal emulator";
      };

      font = {
        family = mkOption {
          type = types.str;
          default = "Consolas";
          description = "Font family for WezTerm";
        };
        size = mkOption {
          type = types.float;
          default = 12.0;
          description = "Font size for WezTerm";
        };
      };

      window = {
        opacity = mkOption {
          type = types.float;
          default = 0.85;
          description = "Window background opacity";
        };
        decorations = mkOption {
          type = types.str;
          default = "RESIZE";
          description = "Window decorations style";
        };
        padding = {
          left = mkOption {
            type = types.int;
            default = 8;
            description = "Left padding";
          };
          right = mkOption {
            type = types.int;
            default = 8;
            description = "Right padding";
          };
          top = mkOption {
            type = types.int;
            default = 6;
            description = "Top padding";
          };
          bottom = mkOption {
            type = types.int;
            default = 6;
            description = "Bottom padding";
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      package = pkgs.wezterm;

      # Color scheme defined in Nix (generates TOML)
      colorSchemes.gruvbox-custom = with colors; {
        ansi = [ base00 base08 base0B base0A base0D base0E base0C base05 ];
        brights = [ base03 base08 base0B base0A base0D base0E base0C base07 ];
        background = base00;
        foreground = base06;
        cursor_bg = base06;
        cursor_fg = base00;
        selection_bg = base02;
        selection_fg = base06;
        split = base03;
        compose_cursor = base09;
        scrollbar_thumb = base01;
        tab_bar = {
          background = base00;
          inactive_tab_edge = base01;
          active_tab = {
            bg_color = base01;
            fg_color = base06;
          };
          inactive_tab = {
            bg_color = base00;
            fg_color = base03;
          };
          inactive_tab_hover = {
            bg_color = base01;
            fg_color = base06;
          };
          new_tab = {
            bg_color = base00;
            fg_color = base03;
          };
          new_tab_hover = {
            bg_color = base01;
            fg_color = base06;
          };
        };
      };

      extraConfig = ''
        local wezterm = require("wezterm")
        local act = wezterm.action
        local config = wezterm.config_builder()

        -- Detect Windows for default shell
        local is_windows = wezterm.target_triple:find("windows") ~= nil
        if is_windows then
          config.default_prog = { "pwsh.exe", "-NoLogo" }
        end

        -- Terminal type (enables undercurl, colored underlines, etc.)
        config.term = "wezterm"

        -- Color scheme (defined in Nix colorSchemes)
        config.color_scheme = "gruvbox-custom"

        -- Font settings
        config.font = wezterm.font("${cfg.font.family}")
        config.font_size = ${toString cfg.font.size}

        -- IME support
        config.use_ime = true

        -- Window appearance
        config.window_background_opacity = ${toString cfg.window.opacity}
        config.window_decorations = "${cfg.window.decorations}"
        config.window_padding = {
          left = ${toString cfg.window.padding.left},
          right = ${toString cfg.window.padding.right},
          top = ${toString cfg.window.padding.top},
          bottom = ${toString cfg.window.padding.bottom},
        }

        -- Tab bar settings
        config.enable_tab_bar = true
        config.hide_tab_bar_if_only_one_tab = true
        config.use_fancy_tab_bar = false
        config.tab_bar_at_bottom = false
        config.show_new_tab_button_in_tab_bar = false

        ${keybind.leaderLua}

        ${keybind.keybindingsLua}

        return config
      '';
    };
  };
}
