from __future__ import annotations

import sys
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.github import GitAuth


class GitAuthTests(unittest.TestCase):
    def test_repr_redacts_token(self) -> None:
        token = "github-token-marker"
        self.assertNotIn(token, repr(GitAuth(token=token)))
