# fzf module - fuzzy finder options
{ lib, ... }:
with lib;
{
  options.myHomeSettings.fzf = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fzf fuzzy finder";
    };

    # Search root directory
    searchRoot = mkOption {
      type = types.str;
      default = "/";
      description = "Root directory for file/directory search";
    };

    # UI options
    height = mkOption {
      type = types.str;
      default = "40%";
      description = "Height of fzf window";
    };

    layout = mkOption {
      type = types.enum [
        "default"
        "reverse"
        "reverse-list"
      ];
      default = "reverse";
      description = "Layout of fzf window";
    };

    border = mkOption {
      type = types.bool;
      default = true;
      description = "Show border around fzf window";
    };

    prompt = mkOption {
      type = types.str;
      default = "> ";
      description = "Prompt string";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional fzf default options";
    };
  };
}
