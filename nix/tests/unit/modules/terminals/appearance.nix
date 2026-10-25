{
  testAppearanceIsNixOwned = {
    expr = import ../../../../modules/terminals/appearance.nix;
    expected = {
      font_family = "UDEV Gothic NF";
      font_size = 10;
      theme = "Catppuccin Mocha";
    };
  };
}
