_: {
  programs.herdr = {
    settings = builtins.fromTOML (builtins.readFile ./config.toml);
  };
  # Take over the previously chezmoi-managed file without creating a backup.
  xdg.configFile."herdr/config.toml".force = true;
}
