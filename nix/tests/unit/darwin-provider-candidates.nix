let
  candidates = import ../../packages/darwin-provider-candidates.nix;
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
        "orca-editor"
      ];
      candidateValues = {
        dia-browser = [ "dia-browser" ];
        orca-editor = [ "orca-editor" ];
      };
    };
  };
}
