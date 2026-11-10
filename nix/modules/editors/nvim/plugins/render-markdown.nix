{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.render-markdown.enable = true;
        keymaps = [
          {
            mode = "n";
            key = "<leader>mp";
            action.__raw = ''function() require("render-markdown").toggle() end'';
            options.desc = "Toggle Markdown rendering";
          }
        ];
      };
    };
}
