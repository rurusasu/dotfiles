{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    { programs.ghostty.enable = true; }
    (lib.mkIf config.programs.ghostty.enable {
      catppuccin.ghostty.enable = true;
      programs.ghostty = {
        package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin pkgs.ghostty-bin;
        systemd.enable = pkgs.stdenv.hostPlatform.isLinux;
        settings = {
          font-family = lib.mkIf config.fonts.fontconfig.enable config.fonts.fontconfig.defaultFonts.monospace;
          font-size = lib.mkIf (config.gtk.font != null) config.gtk.font.size;
          window-theme = "system";
          macos-option-as-alt = true;
          # Herdr owns tabs and panes; Ghostty keeps terminal and window operations.
          keybind = [
            "clear"
            "copy=copy_to_clipboard:mixed"
            "paste=paste_from_clipboard"
            "super+c=copy_to_clipboard:mixed"
            "ctrl+shift+c=copy_to_clipboard:mixed"
            "super+v=paste_from_clipboard"
            "ctrl+shift+v=paste_from_clipboard"
            "super+,=open_config:os_open"
            "ctrl+,=open_config:os_open"
            "super+shift+,=reload_config"
            "ctrl+shift+,=reload_config"
            "super+==increase_font_size:1"
            "super++=increase_font_size:1"
            "ctrl++=increase_font_size:1"
            "ctrl+==increase_font_size:1"
            "super+-=decrease_font_size:1"
            "ctrl+-=decrease_font_size:1"
            "super+0=reset_font_size"
            "ctrl+0=reset_font_size"
            "super+f=start_search"
            "ctrl+shift+f=start_search"
            "performable:escape=end_search"
            "super+g=navigate_search:next"
            "super+shift+g=navigate_search:previous"
            "super+a=select_all"
            "super+k=clear_screen"
            "super+home=scroll_to_top"
            "super+end=scroll_to_bottom"
            "super+page_up=scroll_page_up"
            "super+page_down=scroll_page_down"
            "shift+page_up=scroll_page_up"
            "shift+page_down=scroll_page_down"
            "super+n=new_window"
            "ctrl+shift+n=new_window"
            "super+w=close_window"
            "ctrl+shift+w=close_window"
            "super+q=quit"
            "super+enter=toggle_fullscreen"
            "ctrl+shift+enter=toggle_fullscreen"
            "super+ctrl+f=toggle_fullscreen"
            "super+arrow_right=text:\\x05"
            "super+arrow_left=text:\\x01"
            "super+backspace=text:\\x15"
            "alt+arrow_left=esc:b"
            "alt+arrow_right=esc:f"
          ];
        };
        enableBashIntegration = true;
        enableFishIntegration = false;
        enableZshIntegration = true;
        installBatSyntax = false;
      };
    })
  ];
}
