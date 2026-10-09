# Explicitly reviewed nixpkgs candidates for custom Darwin packages.
# Keep this registry deliberately small: an entry is promoted only after the
# updater has evaluated and built the candidate.
{
  dia-browser = {
    source = "custom";
    nixAttr = null;
    candidates = [ "dia-browser" ];
  };
}
