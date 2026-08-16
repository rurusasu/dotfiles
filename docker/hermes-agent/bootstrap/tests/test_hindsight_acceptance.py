"""Deterministic tests for the Hermes Hindsight live acceptance CLI."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
MODULE_PATH = REPOSITORY_ROOT / "docker" / "hermes-agent" / "hindsight_acceptance.py"
SPEC = importlib.util.spec_from_file_location("hindsight_acceptance", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {MODULE_PATH}")
acceptance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = acceptance
SPEC.loader.exec_module(acceptance)


PROFILES = ("default", "rick", "hoffman", "risarisa", "nancy", "kuroda", "shiraishi")


def valid_extract_response() -> dict[str, Any]:
    return {
        "facts": [
            {
                "text": "Alice moved to Berlin in 2021.",
                "fact_type": "world",
                "entities": ["Alice", "Berlin"],
            }
        ],
        "usage": {"input_tokens": 12, "output_tokens": 8, "total_tokens": 20},
    }


class FakeHttpClient:
    def __init__(
        self,
        base_url: str,
        timeout: float,
        *,
        health: dict[str, Any] | None = None,
        models: tuple[str, ...] = acceptance.REQUIRED_MODELS,
        extract_response: dict[str, Any] | None = None,
        delete_status: int = 204,
        delete_statuses: dict[str, int] | None = None,
        calls: list[tuple[str, str, Any, float]] | None = None,
    ) -> None:
        self.base_url = base_url
        self.timeout = timeout
        self.health = health or {"status": "healthy", "database": "connected"}
        self.models = models
        self.extract_response = extract_response or valid_extract_response()
        self.delete_status = delete_status
        self.delete_statuses = delete_statuses or {}
        self.calls = calls if calls is not None else []

    def request(
        self, method: str, path: str, payload: dict[str, Any] | None = None
    ) -> tuple[int, dict[str, Any]]:
        self.calls.append((method, path, payload, self.timeout))
        if method == "GET" and path == "/health":
            return 200, self.health
        if method == "GET" and path == "/api/tags":
            return 200, {"models": [{"name": name} for name in self.models]}
        if method == "POST" and path.endswith("/memories/dry-run-extract"):
            return 200, self.extract_response
        if method == "DELETE" and path.startswith("/v1/default/banks/"):
            return self.delete_statuses.get(path, self.delete_status), {}
        raise AssertionError(f"Unexpected HTTP request: {method} {path}")


class FakeHttpFactory:
    def __init__(self, **overrides: Any) -> None:
        self.overrides = overrides
        self.calls: list[tuple[str, str, Any, float]] = []
        self.clients: list[FakeHttpClient] = []

    def __call__(self, base_url: str, timeout: float) -> FakeHttpClient:
        client = FakeHttpClient(
            base_url,
            timeout,
            calls=self.calls,
            **self.overrides,
        )
        self.clients.append(client)
        return client


class ProviderWorld:
    def __init__(self) -> None:
        self.memories: dict[str, str] = {}
        self.instances: list[FakeProvider] = []
        self.fail_retain_for: set[str] = set()
        self.leak_cross_profile = False
        self.degraded = False
        self.raise_sync_turn = False

    def factory(self) -> FakeProvider:
        provider = FakeProvider(self)
        self.instances.append(provider)
        return provider


class FakeProvider:
    def __init__(self, world: ProviderWorld) -> None:
        self.world = world
        self.profile = ""
        self.bank_id = ""
        self.home = ""
        self.config: dict[str, Any] = {}
        self.initialized: tuple[str, str, str] | None = None
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.sync_calls = 0
        self.shutdown_calls = 0

    def initialize(self, session_id: str, **kwargs: Any) -> None:
        self.profile = str(kwargs["agent_identity"])
        self.home = os.environ["HERMES_HOME"]
        config_path = Path(self.home) / "hindsight" / "config.json"
        self.config = json.loads(config_path.read_text(encoding="utf-8"))
        self.bank_id = str(self.config["bank_id_template"]).format(profile=self.profile)
        self.initialized = (session_id, self.profile, str(kwargs["platform"]))

    def system_prompt_block(self) -> str:
        return f"# Hindsight Memory\nActive. Bank: {self.bank_id}, budget: mid."

    def handle_tool_call(self, tool_name: str, args: dict[str, Any], **_: Any) -> str:
        self.calls.append((tool_name, dict(args)))
        if self.world.degraded:
            return json.dumps({"error": f"Failed {tool_name}: connection refused"})
        if tool_name == "hindsight_retain":
            if self.profile in self.world.fail_retain_for:
                return json.dumps({"error": "Failed to store memory"})
            self.world.memories[self.bank_id] = str(args["content"])
            return json.dumps({"result": "Memory stored successfully."})
        if tool_name == "hindsight_recall":
            query = str(args["query"])
            if self.world.leak_cross_profile:
                haystack = "\n".join(self.world.memories.values())
            else:
                haystack = self.world.memories.get(self.bank_id, "")
            result = query if query in haystack else "No relevant memories found."
            return json.dumps({"result": result})
        raise AssertionError(f"Unexpected provider tool: {tool_name}")

    def prefetch(self, query: str, *, session_id: str = "") -> str:
        del query, session_id
        return ""

    def sync_turn(
        self, user_content: str, assistant_content: str, *, session_id: str = ""
    ) -> None:
        del user_content, assistant_content, session_id
        self.sync_calls += 1
        if self.world.raise_sync_turn:
            raise RuntimeError("sync failed")

    def shutdown(self) -> None:
        self.shutdown_calls += 1


class StepClock:
    def __init__(self, step: float = 0.125) -> None:
        self.value = 0.0
        self.step = step

    def __call__(self) -> float:
        current = self.value
        self.value += self.step
        return current

    def sleep(self, seconds: float) -> None:
        self.value += seconds


class SequenceClock:
    def __init__(self, values: list[float]) -> None:
        self.values = iter(values)

    def __call__(self) -> float:
        return next(self.values)


class ManualClock:
    def __init__(self) -> None:
        self.value = 0.0

    def __call__(self) -> float:
        return self.value

    def sleep(self, seconds: float) -> None:
        self.value += seconds


class TokenSource:
    def __init__(self) -> None:
        self.value = 0

    def __call__(self, _: int = 16) -> str:
        self.value += 1
        return f"{self.value:032x}"


class HindsightAcceptanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.state = self.root / "acceptance-state.json"
        self.evidence = self.root / "acceptance.json"

    def test_probe_rejects_unhealthy_hindsight_before_extraction(self) -> None:
        http = FakeHttpFactory(health={"status": "degraded", "database": "connected"})

        with self.assertRaisesRegex(acceptance.AcceptanceError, "Hindsight health"):
            acceptance.run_probe(
                api_url="http://hindsight:8888",
                ollama_url="http://ollama:11434",
                strict_probes=20,
                timeout=300,
                evidence_path=self.evidence,
                http_factory=http,
                provider_factory=ProviderWorld().factory,
                token_hex=TokenSource(),
            )

        self.assertEqual([call[1] for call in http.calls], ["/health"])

    def test_probe_rejects_missing_exact_ollama_model_inventory(self) -> None:
        http = FakeHttpFactory(models=("qwen3.6:35b",))

        with self.assertRaisesRegex(acceptance.AcceptanceError, "qwen3-embedding:0.6b"):
            acceptance.run_probe(
                api_url="http://hindsight:8888",
                ollama_url="http://ollama:11434",
                strict_probes=20,
                timeout=300,
                evidence_path=self.evidence,
                http_factory=http,
                provider_factory=ProviderWorld().factory,
                token_hex=TokenSource(),
            )

        self.assertFalse(any(call[0] == "POST" for call in http.calls))

    def test_probe_posts_exact_twenty_alternating_bilingual_schema_requests(
        self,
    ) -> None:
        http = FakeHttpFactory()
        world = ProviderWorld()

        acceptance.run_probe(
            api_url="http://hindsight:8888",
            ollama_url="http://ollama:11434",
            strict_probes=20,
            timeout=300,
            evidence_path=self.evidence,
            http_factory=http,
            provider_factory=world.factory,
            token_hex=TokenSource(),
        )

        posts = [call for call in http.calls if call[0] == "POST"]
        self.assertEqual(len(posts), 20)
        self.assertEqual(
            posts[0][2],
            acceptance.STRICT_PROBE_PAYLOAD
            | {"content": acceptance.CORPUS[0]["content"]},
        )
        self.assertTrue(
            all(
                set(call[2]) == {"content", "retain_mission", "retain_chunk_size"}
                for call in posts
            )
        )
        self.assertEqual(
            [item["language"] for item in acceptance.CORPUS], ["en", "ja"] * 10
        )
        self.assertEqual(
            {item["category"] for item in acceptance.CORPUS},
            {
                "dates",
                "corrections",
                "preferences",
                "entities",
                "relationships",
                "decisions",
            },
        )
        self.assertTrue(
            all(call[1].endswith("/memories/dry-run-extract") for call in posts)
        )
        self.assertEqual(len(world.instances), 1)
        self.assertIn(
            "Bank: test-hermes-default-", world.instances[0].system_prompt_block()
        )

    def test_probe_rejects_invalid_fact_and_usage_schema(self) -> None:
        invalid = valid_extract_response()
        del invalid["facts"][0]["entities"]
        http = FakeHttpFactory(extract_response=invalid)

        with self.assertRaisesRegex(acceptance.AcceptanceError, "entities"):
            acceptance.run_probe(
                api_url="http://hindsight:8888",
                ollama_url="http://ollama:11434",
                strict_probes=20,
                timeout=300,
                evidence_path=self.evidence,
                http_factory=http,
                provider_factory=ProviderWorld().factory,
                token_hex=TokenSource(),
            )

    def test_seed_uses_real_provider_resolution_and_proves_seven_bank_isolation(
        self,
    ) -> None:
        world = ProviderWorld()
        clock = StepClock()

        acceptance.run_seed(
            api_url="http://hindsight:8888",
            profiles=PROFILES,
            timeout=300,
            state_path=self.state,
            provider_factory=world.factory,
            clock=clock,
            sleeper=clock.sleep,
            token_hex=TokenSource(),
        )

        state = json.loads(self.state.read_text(encoding="utf-8"))
        run_id = state["run_id"]
        self.assertEqual(set(state), {"run_id", "banks", "sentinels", "timings"})
        self.assertEqual(
            state["banks"],
            {profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES},
        )
        self.assertEqual(len(set(state["sentinels"].values())), 7)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o600)
        self.assertEqual(len(world.instances), 7)
        self.assertTrue(
            all(instance.home.startswith("/tmp/") for instance in world.instances)
        )
        self.assertTrue(
            all(
                instance.initialized is not None and instance.initialized[2] == "cli"
                for instance in world.instances
            )
        )
        recall_calls = [
            (provider.profile, args["query"])
            for provider in world.instances
            for tool, args in provider.calls
            if tool == "hindsight_recall"
        ]
        self.assertEqual(len(recall_calls), 49)
        for profile in PROFILES:
            self.assertIn((profile, state["sentinels"][profile]), recall_calls)

    def test_seed_retains_each_sentinel_as_a_durable_fact_payload(self) -> None:
        world = ProviderWorld()

        acceptance.run_seed(
            api_url="http://hindsight:8888",
            profiles=PROFILES,
            timeout=300,
            state_path=self.state,
            provider_factory=world.factory,
            clock=StepClock(),
            sleeper=lambda _: None,
            token_hex=TokenSource(),
        )

        state = json.loads(self.state.read_text(encoding="utf-8"))
        retain_calls = {
            provider.profile: args
            for provider in world.instances
            for tool, args in provider.calls
            if tool == "hindsight_retain"
        }
        self.assertEqual(set(retain_calls), set(PROFILES))
        for profile in PROFILES:
            sentinel = state["sentinels"][profile]
            self.assertEqual(
                retain_calls[profile],
                {
                    "content": (
                        "For Hermes acceptance, the durable memory token assigned to "
                        f"profile {profile} is {sentinel}."
                    ),
                    "context": "Hermes acceptance sentinel",
                },
            )

    def test_seed_rejects_cross_profile_sentinel_and_preserves_state(self) -> None:
        world = ProviderWorld()
        world.leak_cross_profile = True

        with self.assertRaisesRegex(acceptance.AcceptanceError, "cross-profile"):
            acceptance.run_seed(
                api_url="http://hindsight:8888",
                profiles=PROFILES,
                timeout=300,
                state_path=self.state,
                provider_factory=world.factory,
                clock=StepClock(),
                sleeper=lambda _: None,
                token_hex=TokenSource(),
            )

        state = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(set(state["banks"]), set(PROFILES))

    def test_seed_failure_preserves_exact_run_banks_without_deletion(self) -> None:
        world = ProviderWorld()
        world.fail_retain_for.add("hoffman")

        with self.assertRaisesRegex(acceptance.AcceptanceError, "retain.*hoffman"):
            acceptance.run_seed(
                api_url="http://hindsight:8888",
                profiles=PROFILES,
                timeout=300,
                state_path=self.state,
                provider_factory=world.factory,
                clock=StepClock(),
                sleeper=lambda _: None,
                token_hex=TokenSource(),
            )

        state = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(set(state["banks"]), set(PROFILES))
        self.assertTrue(
            all(bank.startswith("test-hermes-") for bank in state["banks"].values())
        )

    def test_seed_refuses_to_overwrite_a_preserved_failed_run(self) -> None:
        preserved = '{"run_id":"preserved","banks":{"default":"existing"}}\n'
        self.state.write_text(preserved, encoding="utf-8")
        world = ProviderWorld()

        with self.assertRaisesRegex(acceptance.AcceptanceError, "already exists"):
            acceptance.run_seed(
                api_url="http://hindsight:8888",
                profiles=PROFILES,
                timeout=300,
                state_path=self.state,
                provider_factory=world.factory,
                clock=StepClock(),
                sleeper=lambda _: None,
                token_hex=TokenSource(),
            )

        self.assertEqual(self.state.read_text(encoding="utf-8"), preserved)
        self.assertEqual(world.instances, [])

    def test_seed_rejects_a_retain_that_exceeds_the_operation_budget(self) -> None:
        with self.assertRaisesRegex(acceptance.AcceptanceError, "retain.*300"):
            acceptance.run_seed(
                api_url="http://hindsight:8888",
                profiles=PROFILES,
                timeout=300,
                state_path=self.state,
                provider_factory=ProviderWorld().factory,
                clock=StepClock(step=301),
                sleeper=lambda _: None,
                token_hex=TokenSource(),
            )

        self.assertTrue(self.state.exists())

    def test_recall_rejects_a_result_returned_after_the_total_deadline(self) -> None:
        world = ProviderWorld()
        provider = FakeProvider(world)
        provider.bank_id = "test-bank"
        world.memories[provider.bank_id] = "sentinel"

        with self.assertRaisesRegex(acceptance.AcceptanceError, "recall.*300"):
            acceptance._recall_own_sentinel(
                provider,
                profile="default",
                sentinel="sentinel",
                timeout=300,
                clock=SequenceClock([0.0, 299.0, 299.0, 301.0, 302.0]),
                sleeper=lambda _: None,
                timings=[],
            )

    def test_recall_does_not_start_another_call_without_remaining_budget(self) -> None:
        clock = ManualClock()

        class SlowMissProvider:
            def __init__(self) -> None:
                self.calls = 0

            def handle_tool_call(
                self, tool_name: str, arguments: dict[str, Any]
            ) -> str:
                del tool_name, arguments
                self.calls += 1
                if self.calls > 1:
                    raise AssertionError("second recall must not start")
                clock.value += 299
                return json.dumps({"result": "No relevant memories found."})

        provider = SlowMissProvider()
        with self.assertRaisesRegex(acceptance.AcceptanceError, "recall.*300"):
            acceptance._recall_own_sentinel(
                provider,
                profile="default",
                sentinel="sentinel",
                timeout=300,
                clock=clock,
                sleeper=clock.sleep,
                timings=[],
            )

        self.assertEqual(provider.calls, 1)

    def test_acceptance_state_reservation_is_atomic_between_concurrent_runs(
        self,
    ) -> None:
        barrier = threading.Barrier(2)

        def reserve(run_id: str) -> str:
            barrier.wait()
            try:
                acceptance._create_json_exclusive(self.state, {"run_id": run_id})
            except acceptance.AcceptanceError:
                return "exists"
            return "created"

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(reserve, ("first", "second")))

        self.assertCountEqual(results, ["created", "exists"])
        self.assertIn(
            json.loads(self.state.read_text(encoding="utf-8"))["run_id"],
            {"first", "second"},
        )

    def test_verify_reopens_resolved_banks_after_restart_and_records_percentiles(
        self,
    ) -> None:
        world = ProviderWorld()
        clock = StepClock()
        tokens = TokenSource()
        acceptance.run_seed(
            api_url="http://hindsight:8888",
            profiles=PROFILES,
            timeout=300,
            state_path=self.state,
            provider_factory=world.factory,
            clock=clock,
            sleeper=clock.sleep,
            token_hex=tokens,
        )

        acceptance.run_verify(
            api_url="http://hindsight:8888",
            timeout=300,
            state_path=self.state,
            evidence_path=self.evidence,
            provider_factory=world.factory,
            clock=clock,
            sleeper=clock.sleep,
        )

        evidence = json.loads(self.evidence.read_text(encoding="utf-8"))
        self.assertEqual(evidence["status"], "verified")
        self.assertEqual(evidence["isolation"]["profiles"], 7)
        self.assertEqual(evidence["isolation"]["own_sentinel_recalls"], 7)
        self.assertEqual(evidence["isolation"]["verify_cross_profile_negatives"], 42)
        self.assertEqual(set(evidence["latency_seconds"]), {"retain", "recall"})
        for operation in ("retain", "recall"):
            self.assertIsNotNone(evidence["latency_seconds"][operation]["p50"])
            self.assertIsNotNone(evidence["latency_seconds"][operation]["p95"])
        verify_instances = world.instances[7:]
        self.assertEqual(len(verify_instances), 7)
        self.assertEqual(
            {provider.bank_id for provider in verify_instances},
            set(json.loads(self.state.read_text(encoding="utf-8"))["banks"].values()),
        )

        world.degraded = True
        acceptance.run_degraded(
            api_url="http://hindsight:8888",
            timeout=5,
            state_path=self.state,
            evidence_path=self.evidence,
            provider_factory=world.factory,
            clock=clock,
        )
        acceptance.run_recovery(
            api_url="http://hindsight:8888",
            state_path=self.state,
            evidence_path=self.evidence,
            timeout=300,
            http_factory=FakeHttpFactory(),
        )
        acceptance.run_cleanup(
            api_url="http://hindsight:8888",
            state_path=self.state,
            evidence_path=self.evidence,
            timeout=300,
            http_factory=FakeHttpFactory(),
        )
        evidence = json.loads(self.evidence.read_text(encoding="utf-8"))
        self.assertEqual(evidence["status"], "passed")

    def test_nearest_rank_percentiles_are_sorted_and_one_based(self) -> None:
        values = [9.0, 1.0, 5.0, 3.0, 7.0]

        self.assertEqual(acceptance.nearest_rank(values, 50), 5.0)
        self.assertEqual(acceptance.nearest_rank(values, 95), 9.0)
        self.assertIsNone(acceptance.nearest_rank([], 50))

    def test_timeout_is_propagated_to_http_and_provider_config(self) -> None:
        http = FakeHttpFactory()
        world = ProviderWorld()

        acceptance.run_probe(
            api_url="http://hindsight:8888",
            ollama_url="http://ollama:11434",
            strict_probes=20,
            timeout=17,
            evidence_path=self.evidence,
            http_factory=http,
            provider_factory=world.factory,
            token_hex=TokenSource(),
        )

        self.assertTrue(all(call[3] == 17 for call in http.calls))
        self.assertEqual(world.instances[0].config["timeout"], 17)

    def test_provider_factory_failure_restores_the_process_hermes_home(self) -> None:
        http = FakeHttpFactory()
        original_home = os.environ.get("HERMES_HOME")
        os.environ["HERMES_HOME"] = "/tmp/original-hermes-home"

        def fail_provider() -> FakeProvider:
            raise RuntimeError("provider construction failed")

        try:
            with self.assertRaisesRegex(RuntimeError, "provider construction failed"):
                acceptance.run_probe(
                    api_url="http://hindsight:8888",
                    ollama_url="http://ollama:11434",
                    strict_probes=20,
                    timeout=300,
                    evidence_path=self.evidence,
                    http_factory=http,
                    provider_factory=fail_provider,
                    token_hex=TokenSource(),
                )
            self.assertEqual(os.environ.get("HERMES_HOME"), "/tmp/original-hermes-home")
        finally:
            if original_home is None:
                os.environ.pop("HERMES_HOME", None)
            else:
                os.environ["HERMES_HOME"] = original_home

    def test_degraded_requires_empty_prefetch_bounded_sync_and_failed_tools(
        self,
    ) -> None:
        world = ProviderWorld()
        clock = StepClock()
        acceptance.run_seed(
            api_url="http://hindsight:8888",
            profiles=PROFILES,
            timeout=300,
            state_path=self.state,
            provider_factory=world.factory,
            clock=clock,
            sleeper=clock.sleep,
            token_hex=TokenSource(),
        )
        state = json.loads(self.state.read_text(encoding="utf-8"))
        self.evidence.write_text(
            json.dumps(
                {
                    "status": "verified",
                    "run_id": state["run_id"],
                    "banks": state["banks"],
                }
            ),
            encoding="utf-8",
        )
        world.degraded = True

        acceptance.run_degraded(
            api_url="http://hindsight:8888",
            timeout=5,
            state_path=self.state,
            evidence_path=self.evidence,
            provider_factory=world.factory,
            clock=clock,
        )

        degraded_provider = world.instances[-1]
        self.assertEqual(degraded_provider.profile, "default")
        self.assertEqual(degraded_provider.sync_calls, 1)
        self.assertEqual(degraded_provider.shutdown_calls, 1)
        self.assertEqual(
            [tool for tool, _ in degraded_provider.calls],
            ["hindsight_retain", "hindsight_recall"],
        )
        self.assertTrue(self.state.exists())
        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "degraded",
        )

    def test_recovery_requires_degraded_evidence_and_connected_hindsight(self) -> None:
        run_id = "e" * 32
        state = {
            "run_id": run_id,
            "banks": {
                profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES
            },
            "sentinels": {profile: f"sentinel-{profile}" for profile in PROFILES},
            "timings": {"retain": [1.0], "recall": [2.0]},
        }
        self.state.write_text(json.dumps(state), encoding="utf-8")
        self.evidence.write_text(
            json.dumps(
                {
                    "status": "degraded",
                    "run_id": run_id,
                    "banks": state["banks"],
                }
            ),
            encoding="utf-8",
        )

        acceptance.run_recovery(
            api_url="http://hindsight:8888",
            state_path=self.state,
            evidence_path=self.evidence,
            timeout=300,
            http_factory=FakeHttpFactory(),
        )

        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "recovered",
        )

    def test_cleanup_refuses_any_nonexact_or_nonowned_bank_before_delete(self) -> None:
        run_id = "a" * 32
        state = {
            "run_id": run_id,
            "banks": {
                profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES
            },
            "sentinels": {profile: f"sentinel-{profile}" for profile in PROFILES},
            "timings": {"retain": [], "recall": []},
        }
        state["banks"]["default"] = "test-hermes-default"
        self.state.write_text(json.dumps(state), encoding="utf-8")
        http = FakeHttpFactory()

        with self.assertRaisesRegex(acceptance.AcceptanceError, "unsafe test bank"):
            acceptance.run_cleanup(
                api_url="http://hindsight:8888",
                state_path=self.state,
                evidence_path=self.evidence,
                timeout=300,
                http_factory=http,
            )

        self.assertEqual(http.calls, [])
        self.assertTrue(self.state.exists())

    def test_cleanup_deletes_only_all_exact_run_owned_banks_then_removes_state(
        self,
    ) -> None:
        run_id = "b" * 32
        state = {
            "run_id": run_id,
            "banks": {
                profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES
            },
            "sentinels": {profile: f"sentinel-{profile}" for profile in PROFILES},
            "timings": {"retain": [1.0], "recall": [2.0]},
        }
        self.state.write_text(json.dumps(state), encoding="utf-8")
        self.evidence.write_text(
            json.dumps(
                {"status": "recovered", "run_id": run_id, "banks": state["banks"]}
            ),
            encoding="utf-8",
        )
        http = FakeHttpFactory()

        acceptance.run_cleanup(
            api_url="http://hindsight:8888",
            state_path=self.state,
            evidence_path=self.evidence,
            timeout=300,
            http_factory=http,
        )

        deletes = [call for call in http.calls if call[0] == "DELETE"]
        self.assertEqual(
            [call[1] for call in deletes],
            [f"/v1/default/banks/{state['banks'][profile]}" for profile in PROFILES],
        )
        self.assertFalse(self.state.exists())
        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "passed",
        )

    def test_cleanup_refuses_to_delete_before_recovery_is_complete(self) -> None:
        run_id = "d" * 32
        state = {
            "run_id": run_id,
            "banks": {
                profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES
            },
            "sentinels": {profile: f"sentinel-{profile}" for profile in PROFILES},
            "timings": {"retain": [1.0], "recall": [2.0]},
        }
        self.state.write_text(json.dumps(state), encoding="utf-8")
        self.evidence.write_text(
            json.dumps(
                {"status": "verified", "run_id": run_id, "banks": state["banks"]}
            ),
            encoding="utf-8",
        )
        http = FakeHttpFactory()

        with self.assertRaisesRegex(acceptance.AcceptanceError, "recovered"):
            acceptance.run_cleanup(
                api_url="http://hindsight:8888",
                state_path=self.state,
                evidence_path=self.evidence,
                timeout=300,
                http_factory=http,
            )

        self.assertEqual(http.calls, [])
        self.assertTrue(self.state.exists())
        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "verified",
        )

    def test_cleanup_retries_after_partial_delete_and_accepts_owned_bank_404(
        self,
    ) -> None:
        run_id = "c" * 32
        state = {
            "run_id": run_id,
            "banks": {
                profile: f"test-hermes-{profile}-{run_id}" for profile in PROFILES
            },
            "sentinels": {profile: f"sentinel-{profile}" for profile in PROFILES},
            "timings": {"retain": [1.0], "recall": [2.0]},
        }
        self.state.write_text(json.dumps(state), encoding="utf-8")
        self.evidence.write_text(
            json.dumps(
                {"status": "recovered", "run_id": run_id, "banks": state["banks"]}
            ),
            encoding="utf-8",
        )
        paths = {
            profile: f"/v1/default/banks/{state['banks'][profile]}"
            for profile in PROFILES
        }
        partial = FakeHttpFactory(delete_statuses={paths["rick"]: 500})

        with self.assertRaisesRegex(acceptance.AcceptanceError, "HTTP 500"):
            acceptance.run_cleanup(
                api_url="http://hindsight:8888",
                state_path=self.state,
                evidence_path=self.evidence,
                timeout=300,
                http_factory=partial,
            )

        self.assertEqual(
            [call[1] for call in partial.calls if call[0] == "DELETE"],
            [paths["default"], paths["rick"]],
        )
        self.assertTrue(self.state.exists())
        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "recovered",
        )

        retry = FakeHttpFactory(delete_statuses={paths["default"]: 404})
        acceptance.run_cleanup(
            api_url="http://hindsight:8888",
            state_path=self.state,
            evidence_path=self.evidence,
            timeout=300,
            http_factory=retry,
        )

        self.assertEqual(
            [call[1] for call in retry.calls if call[0] == "DELETE"],
            [paths[profile] for profile in PROFILES],
        )
        self.assertFalse(self.state.exists())
        self.assertEqual(
            json.loads(self.evidence.read_text(encoding="utf-8"))["status"],
            "passed",
        )


if __name__ == "__main__":
    unittest.main()
