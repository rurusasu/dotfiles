_: {
  programs.herdr = {
    enable = true;
    settings = builtins.fromTOML (builtins.readFile ./config.toml);
  };
}
