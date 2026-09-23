{ inputs }:
let
  candidates = import ../packages/darwin-provider-candidates.nix;
in
{
  testDockerDesktopIsNotACustomDarwinProviderCandidate = {
    expr = builtins.hasAttr "docker-desktop" candidates;
    expected = false;
  };
}
