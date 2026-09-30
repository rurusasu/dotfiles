from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


HERMES_ROOT = Path("/opt/hermes")


class DistributionFilterContractTests(unittest.TestCase):
    def test_installer_copies_only_manifest_owned_roots(self) -> None:
        if not (HERMES_ROOT / "hermes_cli/profile_distribution.py").is_file():
            self.skipTest("Hermes runtime source is only available in the image")

        sys.path.insert(0, str(HERMES_ROOT))
        from hermes_cli.profile_distribution import (
            _copy_dist_payload,
            read_manifest,
        )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            staged = root / "staged"
            target = root / "target"
            staged.mkdir()
            (staged / "distribution.yaml").write_text(
                """\
name: fixture
version: 0.1.0
distribution_owned:
  - SOUL.md
  - config.yaml
  - assets/
""",
                encoding="utf-8",
            )
            (staged / "SOUL.md").write_text("fixture\n", encoding="utf-8")
            (staged / "config.yaml").write_text("{}\n", encoding="utf-8")
            (staged / "assets").mkdir()
            (staged / "assets/avatar.txt").write_text("fixture\n", encoding="utf-8")
            (staged / ".github").mkdir()
            (staged / ".github/workflow.yml").write_text("unowned\n", encoding="utf-8")
            (staged / "tests").mkdir()
            (staged / "tests/test_fixture.py").write_text("unowned\n", encoding="utf-8")

            manifest = read_manifest(staged)
            self.assertIsNotNone(manifest)
            assert manifest is not None
            _copy_dist_payload(staged, target, manifest, preserve_config=False)

            self.assertTrue((target / "SOUL.md").is_file())
            self.assertTrue((target / "config.yaml").is_file())
            self.assertTrue((target / "assets/avatar.txt").is_file())
            self.assertTrue((target / "distribution.yaml").is_file())
            self.assertFalse((target / ".github").exists())
            self.assertFalse((target / "tests").exists())


if __name__ == "__main__":
    unittest.main()
