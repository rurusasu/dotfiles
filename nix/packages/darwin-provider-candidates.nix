# Explicitly reviewed nixpkgs candidates for custom Darwin packages.
# Keep this registry deliberately small: an entry is promoted only after the
# updater has evaluated, built, and identity-checked the candidate.
{
  dia-browser = {
    source = "custom";
    nixAttr = null;
    candidates = [ "dia-browser" ];
  };
  orca-editor = {
    source = "custom";
    nixAttr = null;
    candidates = [ "orca-editor" ];
  };
  hammerspoon = {
    source = "custom";
    nixAttr = null;
    candidates = [ "hammerspoon" ];
  };
  docker-desktop = {
    source = "custom";
    nixAttr = null;
    candidates = [ "docker-desktop" ];
  };
}
