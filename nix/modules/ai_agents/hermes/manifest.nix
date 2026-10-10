{ hermesHome }:
builtins.replaceStrings [ "/opt/data" ] [ hermesHome ] (builtins.readFile ./manifest.yaml)
