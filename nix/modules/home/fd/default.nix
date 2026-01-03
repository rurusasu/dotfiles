# fd module - file finder options
{ lib, ... }:
with lib;
{
  options.myHomeSettings.fd = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fd file finder";
    };

    hidden = mkOption {
      type = types.bool;
      default = true;
      description = "Search hidden files and directories (--hidden)";
    };

    followSymlinks = mkOption {
      type = types.bool;
      default = true;
      description = "Follow symbolic links (--follow)";
    };

    noIgnoreVcs = mkOption {
      type = types.bool;
      default = true;
      description = "Do not respect .gitignore (--no-ignore-vcs)";
    };

    maxResults = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Maximum number of search results (--max-results). null = unlimited";
    };

    maxDepth = mkOption {
      type = types.nullOr types.int;
      default = 10;
      description = "Maximum search depth (--max-depth)";
    };

    ignores = mkOption {
      type = types.listOf types.str;
      default = [
        ".git/"
        "node_modules/"
        "target/"
        "__pycache__/"
        ".cache/"
        ".nix-profile/"
        ".local/share/"
        ".npm/"
        ".cargo/"
        "/mnt/wsl/"
        "/mnt/wslg/"
        "/sys/"
        "/lib/"
      ];
      description = "Paths to ignore globally";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional fd options";
    };
  };
}
