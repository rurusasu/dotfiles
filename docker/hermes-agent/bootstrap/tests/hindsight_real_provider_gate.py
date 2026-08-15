"""Docker-only gate for the bundled Hindsight provider resolver.

The filename intentionally stays outside unittest's default ``test*.py``
pattern.  The Docker test stage invokes it explicitly because the host test
environment does not include Hermes' bundled provider package.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import unittest
from pathlib import Path

from plugins.memory.hindsight import HindsightMemoryProvider

MODULE_PATH = Path("/workspace/docker/hermes-agent/hindsight_acceptance.py")
SPEC = importlib.util.spec_from_file_location(
    "hindsight_acceptance_real_gate", MODULE_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {MODULE_PATH}")
acceptance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = acceptance
SPEC.loader.exec_module(acceptance)

PROFILES = (
    "default",
    "rick",
    "hoffman",
    "risarisa",
    "nancy",
    "kuroda",
    "shiraishi",
)
RUN_ID = "0123456789abcdef0123456789abcdef"


class RealBundledProviderGateTests(unittest.TestCase):
    def test_all_profiles_resolve_exact_banks_through_the_production_factory(
        self,
    ) -> None:
        original_home = os.environ.get("HERMES_HOME")
        resolved_banks: list[str] = []

        for profile in PROFILES:
            with self.subTest(profile=profile):
                expected_bank = f"test-hermes-{profile}-{RUN_ID}"
                with acceptance._resolved_provider(
                    profile=profile,
                    run_id=RUN_ID,
                    api_url="http://hindsight.invalid:8888",
                    timeout=300,
                    provider_factory=None,
                ) as (provider, bank):
                    self.assertIs(type(provider), HindsightMemoryProvider)
                    self.assertEqual(bank, expected_bank)

                    hermes_home = Path(os.environ["HERMES_HOME"])
                    self.assertEqual(hermes_home.parent, Path("/tmp"))
                    self.assertTrue(
                        hermes_home.name.startswith("hermes-hindsight-")
                    )
                    config_path = hermes_home / "hindsight" / "config.json"
                    self.assertEqual(stat.S_IMODE(config_path.stat().st_mode), 0o600)

                    config = json.loads(config_path.read_text(encoding="utf-8"))
                    self.assertEqual(
                        config["bank_id"],
                        "acceptance-resolver-fallback-must-not-be-used",
                    )
                    self.assertEqual(
                        config["bank_id_template"],
                        f"test-hermes-{{profile}}-{RUN_ID}",
                    )
                    self.assertEqual(
                        provider._session_id,
                        f"acceptance-{RUN_ID}-{profile}",
                    )
                    self.assertEqual(provider._agent_identity, profile)
                    self.assertEqual(provider._platform, "cli")
                    self.assertEqual(provider._bank_id, expected_bank)
                    self.assertEqual(
                        provider.system_prompt_block(),
                        "# Hindsight Memory\n"
                        f"Active. Bank: {expected_bank}, budget: mid.\n"
                        "Relevant memories are automatically injected into context. "
                        "Use hindsight_recall to search, hindsight_reflect for "
                        "synthesis, hindsight_retain to store facts.",
                    )
                    resolved_banks.append(bank)

                self.assertEqual(os.environ.get("HERMES_HOME"), original_home)

        self.assertEqual(
            resolved_banks,
            [f"test-hermes-{profile}-{RUN_ID}" for profile in PROFILES],
        )


if __name__ == "__main__":
    unittest.main()
