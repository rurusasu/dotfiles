{ typescript-language-server }:
let
  upstream = typescript-language-server;
  brokenHash = "sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo=";
  correctedHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
in
if
  upstream.version == "6.0.2" && upstream ? pnpmDeps && upstream.pnpmDeps.outputHash == brokenHash
then
  # Carry https://github.com/NixOS/nixpkgs/pull/572951 until nixos-unstable includes it.
  upstream.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.override { hash = correctedHash; };
  })
else
  upstream
