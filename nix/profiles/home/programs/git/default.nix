{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      safe.directory = "*";
    };
  };
}
