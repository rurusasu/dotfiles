"""Entry point for the dotfiles-managed Hermes bootstrap CLI.

Hermes itself ships a top-level ``hermes_bootstrap.py`` module, so invoking
``python -m hermes_bootstrap`` can resolve to upstream code instead of this
repository's ``hermes_bootstrap`` package. Executing this file puts its own
directory first on ``sys.path`` and makes the intended package unambiguous.
"""

from hermes_bootstrap.cli import main


if __name__ == "__main__":
    raise SystemExit(main())
