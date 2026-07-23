from __future__ import annotations

import sys
import unittest
from pathlib import Path


HERMES_ROOT = Path("/opt/hermes")
BROWSER_AUTOMATION_TOOLS = {
    "browser_navigate",
    "browser_snapshot",
    "browser_click",
    "browser_type",
    "browser_scroll",
    "browser_back",
    "browser_press",
    "browser_get_images",
    "browser_vision",
    "browser_console",
    "browser_cdp",
    "browser_dialog",
}


class ToolsetContractTests(unittest.TestCase):
    def test_browser_toolset_excludes_web_search_without_losing_automation_tools(
        self,
    ) -> None:
        if not (HERMES_ROOT / "toolsets.py").is_file():
            self.skipTest("Hermes runtime source is only available in the image")

        sys.path.insert(0, str(HERMES_ROOT))
        from toolsets import resolve_toolset

        browser_tools = set(resolve_toolset("browser"))
        self.assertEqual(browser_tools, BROWSER_AUTOMATION_TOOLS)
        self.assertNotIn("web_search", browser_tools)
        self.assertIn("web_search", resolve_toolset("web"))


if __name__ == "__main__":
    unittest.main()
