{
  pkgs,
  fixtures,
  code,
  files,
}:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [ (fixtures.homeModule "common") ];
  generated = code.nix.home.appearance {
    config = home.config;
    inherit pkgs;
  };
in
{
  appearance-export = pkgs.runCommand "appearance-export-check" { } ''
    cmp ${generated} ${files.nix.home."appearance.json"}
    touch "$out"
  '';
}
