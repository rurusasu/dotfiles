{ code }:
{
  testAppearanceIsNixOwned = {
    expr = code.nix.modules.terminals.appearance;
    expected = {
      font_family = "UDEV Gothic NF";
      font_size = 10;
      theme = "Catppuccin Mocha";
    };
  };
}
