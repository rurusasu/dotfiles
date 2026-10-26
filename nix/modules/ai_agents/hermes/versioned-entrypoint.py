"""Keep the Nix source date consistent with the packaged source identity."""

import runpy
import sys

import hermes_cli

# Use the immutable source date supplied by Nix, never the machine's clock.
hermes_cli.__release_date__ = sys.argv.pop(1)
entrypoint = sys.argv.pop(1)
runpy.run_path(entrypoint, run_name="__main__")
