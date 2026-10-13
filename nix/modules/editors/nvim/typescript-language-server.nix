{ typescript-language-server }:
# Remove once nixos-unstable includes NixOS/nixpkgs@ac7b1aaed03db4b794502641cdeed685ed777889.
# Apply the upstream fix only to the broken dependency hash; other versions stay unchanged.
if
  (typescript-language-server.pnpmDeps.outputHash or null)
  == "sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo="
then
  typescript-language-server.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
      outputHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
    });
  })
else
  typescript-language-server
