{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.which-key = {
          enable = true;
          settings.triggers = [
            {
              __unkeyed-1 = "<auto>";
              mode = "nixsotc";
            }
            {
              __unkeyed-1 = "<leader>";
              mode = "n";
            }
          ];
        };
      };
    };
}
