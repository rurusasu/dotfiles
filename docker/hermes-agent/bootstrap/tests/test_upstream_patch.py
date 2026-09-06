from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.upstream_patch import (
    BROWSER_TOOLSET_VARIANTS,
    COMPREHENSION_BROWSER_TOOLSET,
    COMPREHENSION_BROWSER_TOOLSET_PATCHED,
    FIXED_BROWSER_TOOLSET,
    LEGACY_EXPLICIT_BROWSER_TOOLSET,
    LEGACY_EXPLICIT_BROWSER_TOOLSET_PATCHED,
    replace_pattern_variant_once,
)


class UpstreamPatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "toolsets.py"

    def apply(self, source: str) -> str:
        self.path.write_text("# before\n" + source + "# after\n", encoding="utf-8")
        replace_pattern_variant_once(self.path, BROWSER_TOOLSET_VARIANTS)
        return self.path.read_text(encoding="utf-8")

    def test_accepts_and_normalizes_supported_browser_toolset_shapes(self) -> None:
        supported = {
            "explicit": (
                LEGACY_EXPLICIT_BROWSER_TOOLSET,
                LEGACY_EXPLICIT_BROWSER_TOOLSET_PATCHED,
            ),
            "comprehension_with_web_search": (
                COMPREHENSION_BROWSER_TOOLSET,
                COMPREHENSION_BROWSER_TOOLSET_PATCHED,
            ),
            "already_fixed": (FIXED_BROWSER_TOOLSET, FIXED_BROWSER_TOOLSET),
        }

        for name, (source, expected) in supported.items():
            with self.subTest(name=name):
                self.assertEqual(
                    self.apply(source),
                    "# before\n" + expected + "# after\n",
                )

    def test_rejects_unknown_or_ambiguous_browser_toolset_shapes(self) -> None:
        unsupported = {
            "spaced_list": COMPREHENSION_BROWSER_TOOLSET.replace(
                '["web_search"]',
                '[ "web_search" ]',
            ),
            "single_quotes": COMPREHENSION_BROWSER_TOOLSET.replace(
                '["web_search"]',
                "['web_search']",
            ),
            "unknown_concatenation": COMPREHENSION_BROWSER_TOOLSET.replace(
                '["web_search"]',
                "EXTRA_TOOLS",
            ),
            "trailing_argument": FIXED_BROWSER_TOOLSET.replace(
                "    ),\n",
                "        posture=True,\n    ),\n",
            ),
            "repeated": FIXED_BROWSER_TOOLSET + FIXED_BROWSER_TOOLSET,
            "combined": COMPREHENSION_BROWSER_TOOLSET + FIXED_BROWSER_TOOLSET,
            "unknown": '    "browser": _ts("unknown", BROWSER_TOOLS),\n',
        }

        for name, source in unsupported.items():
            with self.subTest(name=name):
                self.path.write_text("# before\n" + source + "# after\n", encoding="utf-8")
                with self.assertRaisesRegex(
                    SystemExit, "expected exactly one supported source variant"
                ):
                    replace_pattern_variant_once(
                        self.path,
                        BROWSER_TOOLSET_VARIANTS,
                    )


if __name__ == "__main__":
    unittest.main()
