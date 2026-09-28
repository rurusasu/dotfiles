# Shared derivation adapters used by catalog categories.
{ pkgs }:
let
  # The same appearance data is consumed by chezmoi templates and exposed to
  # Nix consumers so font/theme values do not drift by platform.
  appearance =
    (builtins.fromJSON (builtins.readFile ../../../chezmoi/.chezmoidata/appearance.json)).appearance;
  darwinProviderCandidates = import ../darwin-provider-candidates.nix;
  darwinProviderCandidate = name: darwinProviderCandidates.${name};
  selectDarwinPackage =
    name: customPackage:
    let
      candidate = darwinProviderCandidate name;
    in
    if candidate.source == "nixpkgs" then builtins.getAttr candidate.nixAttr pkgs else customPackage;
  darwinDiscordPackage =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.discord.overrideAttrs (old: {
        dontFixup = true;
        postInstall = (old.postInstall or "") + ''
          mkdir -p "$out/share/discord"
          mv "$out/Applications/Discord.app/Contents/Resources/modules" "$out/share/discord/modules"
          substituteInPlace "$out/bin/Discord" \
            --replace-fail \
            "$out/Applications/Discord.app/Contents/Resources/modules" \
            "$out/share/discord/modules"
        '';
      })
    else
      null;
in
{
  inherit
    appearance
    selectDarwinPackage
    darwinProviderCandidate
    darwinDiscordPackage
    ;
}
