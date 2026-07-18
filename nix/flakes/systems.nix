{ inputs, ... }:
{
  # Current nixpkgs unstable has dropped x86_64-darwin; this repository supports Apple Silicon macOS.
  systems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);
}
