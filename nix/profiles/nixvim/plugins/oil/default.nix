# oil.nvim - file explorer that lets you edit your filesystem like a buffer
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.oil = {
      enable = true;
      package = pkgs.vimPlugins.oil-nvim;
      settings = {
        # Delete files to trash instead of permanently
        delete_to_trash = true;
        # Skip confirmation for simple operations
        skip_confirm_for_simple_edits = true;
        # Use default keymaps
        use_default_keymaps = true;
        # Show hidden files
        view_options = {
          show_hidden = true;
        };
        # Keymaps within oil buffer
        keymaps = {
          "g?" = "actions.show_help";
          "<CR>" = "actions.select";
          "<C-v>" = "actions.select_vsplit";
          "<C-s>" = "actions.select_split";
          "<C-t>" = "actions.select_tab";
          "<C-p>" = "actions.preview";
          "<C-c>" = "actions.close";
          "<C-r>" = "actions.refresh";
          "-" = "actions.parent";
          "_" = "actions.open_cwd";
          "`" = "actions.cd";
          "~" = "actions.tcd";
          "gs" = "actions.change_sort";
          "gx" = "actions.open_external";
          "g." = "actions.toggle_hidden";
        };
      };
    };

    # Add keymap to open oil
    programs.nixvim.keymaps = [
      {
        mode = "n";
        key = "-";
        action = "<cmd>Oil<cr>";
        options.desc = "Open parent directory (Oil)";
      }
    ];
  };
}
