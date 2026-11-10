{
  pkgs,
  fixtures,
  code,
  files,
}:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [ (fixtures.homeModule "common") ];
  generated = code.chezmoi.appearance.export {
    inherit (home) config;
    inherit pkgs;
  };
in
{
  appearance-export = pkgs.runCommand "appearance-export-check" { } ''
    cmp ${generated} ${files.chezmoi.appearance."appearance.json"}
    touch "$out"
  '';
}
