let
  candidates = import ../packages/darwin-provider-candidates.nix;
in
{
  testDarwinProviderCandidateRegistry = {
    expr = {
      registryKeys = builtins.attrNames candidates;
      candidateValues = builtins.mapAttrs (_: entry: entry.candidates) candidates;
    };
    expected = {
      registryKeys = [
        "dia-browser"
        "hammerspoon"
        "orca-editor"
      ];
      candidateValues = {
        dia-browser = [ "dia-browser" ];
        hammerspoon = [ "hammerspoon" ];
        orca-editor = [ "orca-editor" ];
      };
    };
  };
}
