{ inputs, pkgs }:
# Realize the unmodified official package separately from our bootstrap tests.
# This check preserves full-feature package coverage without coupling every
# unrelated shell/configuration test to Hermes' complete dependency closure.
inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
