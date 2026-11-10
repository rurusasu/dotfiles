# Export the managed desktop preferences for native Windows applications.
{ config, pkgs }:
pkgs.runCommand "dotfiles-appearance.json"
  {
    nativeBuildInputs = [ pkgs.jq ];
    palette = config.catppuccin.sources.palette;
    flavor = config.catppuccin.flavor;
    fontFamily = builtins.head config.fonts.fontconfig.defaultFonts.monospace;
    fontSize = toString config.gtk.font.size;
  }
  ''
    jq --arg flavor "$flavor" --arg fontFamily "$fontFamily" --argjson fontSize "$fontSize" '
      .[$flavor] as $palette | $palette.colors as $c |
      {
        fontFamily: $fontFamily,
        fontSize: $fontSize,
        superfileTheme: ("catppuccin-" + $flavor),
        windowsTerminalScheme: {
          name: ("Catppuccin " + $palette.name),
          background: $c.base.hex, foreground: $c.text.hex,
          cursorColor: $c.rosewater.hex, selectionBackground: $c.surface2.hex,
          black: $c.surface1.hex, brightBlack: $c.surface2.hex,
          red: $c.red.hex, brightRed: $c.red.hex,
          green: $c.green.hex, brightGreen: $c.green.hex,
          yellow: $c.yellow.hex, brightYellow: $c.yellow.hex,
          blue: $c.blue.hex, brightBlue: $c.blue.hex,
          purple: $c.pink.hex, brightPurple: $c.pink.hex,
          cyan: $c.teal.hex, brightCyan: $c.teal.hex,
          white: $c.subtext1.hex, brightWhite: $c.subtext0.hex
        }
      }
    ' "$palette/palette.json" > "$out"
  ''
