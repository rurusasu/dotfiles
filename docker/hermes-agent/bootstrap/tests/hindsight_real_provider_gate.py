"""Docker-only gate for Hermes' discovered Hindsight provider.

The filename intentionally stays outside unittest's default ``test*.py``
pattern.  The Docker test stage invokes it explicitly because the host test
environment does not include Hermes' bundled provider package.
"""

from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import queue
import stat
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

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


class RealDiscoveredProviderGateTests(unittest.TestCase):
    def test_provider_async_bridge_runs_coroutines_and_closes_them_on_loop_failure(
        self,
    ) -> None:
        with acceptance._resolved_provider(
            profile="default",
            run_id=RUN_ID,
            api_url="http://127.0.0.1:9",
            timeout=1,
            provider_factory=None,
        ) as (provider, _):
            module = sys.modules[type(provider).__module__]

            async def result():
                return "scheduled"

            self.assertEqual(module._run_sync(result(), timeout=2), "scheduled")
            closed_loop = asyncio.new_event_loop()
            closed_loop.close()
            for loop in (None, closed_loop):
                with (
                    self.subTest(loop=loop),
                    patch.object(module, "_get_loop", return_value=loop),
                ):
                    coroutine = result()
                    with self.assertRaisesRegex(
                        RuntimeError, "Hindsight loop unavailable"
                    ):
                        module._run_sync(coroutine, timeout=1)
                    self.assertIsNone(coroutine.cr_frame)

    def test_writer_preserves_the_calling_profiles_home_and_secret_scope(self) -> None:
        from agent.secret_scope import get_secret, reset_secret_scope, set_secret_scope
        from hermes_constants import (
            get_hermes_home,
            reset_hermes_home_override,
            set_hermes_home_override,
        )

        for profile in ("rick", "nancy"):
            with (
                self.subTest(profile=profile),
                acceptance._resolved_provider(
                    profile=profile,
                    run_id=RUN_ID,
                    api_url="http://127.0.0.1:9",
                    timeout=1,
                    provider_factory=None,
                ) as (provider, _),
            ):
                scoped_home = f"/tmp/acceptance-worker-{profile}"
                home_token = set_hermes_home_override(scoped_home)
                secret_token = set_secret_scope({"HINDSIGHT_API_KEY": profile})
                observed = queue.Queue()
                try:
                    provider._enqueue_retain(
                        lambda observed=observed: observed.put(
                            (str(get_hermes_home()), get_secret("HINDSIGHT_API_KEY"))
                        )
                    )
                finally:
                    reset_secret_scope(secret_token)
                    reset_hermes_home_override(home_token)
                self.assertEqual(observed.get(timeout=2), (scoped_home, profile))

    def test_provider_saves_config_without_losing_the_isolated_bank(self) -> None:
        with acceptance._resolved_provider(
            profile="rick",
            run_id=RUN_ID,
            api_url="http://127.0.0.1:9",
            timeout=1,
            provider_factory=None,
        ) as (provider, _):
            home = os.environ["HERMES_HOME"]
            provider.save_config({"recall_budget": "high"}, home)
            saved = json.loads((Path(home) / "hindsight/config.json").read_text())
            self.assertEqual(saved["recall_budget"], "high")
            self.assertEqual(
                saved["bank_id_template"], f"test-hermes-{{profile}}-{RUN_ID}"
            )

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
                    self.assertEqual(type(provider).__name__, "HindsightMemoryProvider")
                    self.assertEqual(bank, expected_bank)

                    hermes_home = Path(os.environ["HERMES_HOME"])
                    self.assertEqual(hermes_home.parent, Path("/tmp"))
                    self.assertTrue(hermes_home.name.startswith("hermes-hindsight-"))
                    hermes_config_path = hermes_home / "config.yaml"
                    self.assertEqual(
                        hermes_config_path.read_text(encoding="utf-8"),
                        "memory:\n  provider: hindsight\n",
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
