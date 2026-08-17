"""Unit tests for the in-container Hermes Gateway convergence command."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path


MODULE_PATH = Path(__file__).parents[2] / "gateway_convergence.py"
SPEC = importlib.util.spec_from_file_location("gateway_convergence", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
gateway_convergence = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gateway_convergence
SPEC.loader.exec_module(gateway_convergence)


class FakeManager:
    def __init__(
        self,
        profiles: tuple[str, ...],
        *,
        on_start: Callable[[str], None] | None = None,
        start_errors: dict[str, Exception] | None = None,
    ) -> None:
        self.profiles = profiles
        self.started: list[str] = []
        self.running = {f"gateway-{profile}": True for profile in profiles}
        self.on_start = on_start
        self.start_errors = start_errors or {}

    def list_profile_gateways(self) -> list[str]:
        return list(self.profiles)

    def start(self, service_name: str) -> None:
        self.started.append(service_name)
        if service_name in self.start_errors:
            raise self.start_errors[service_name]
        if self.on_start is not None:
            self.on_start(service_name)

    def is_running(self, service_name: str) -> bool:
        return self.running[service_name]


def write_ready_state(root: Path, profile: str, *, discord: bool) -> None:
    home = root if profile == "default" else root / "profiles" / profile
    home.mkdir(parents=True, exist_ok=True)
    state: dict[str, object] = {"desired_state": "running"}
    if discord:
        state["platforms"] = {"discord": {"state": "connected"}}
    (home / "gateway_state.json").write_text(
        json.dumps(state), encoding="utf-8"
    )


def write_gateway_state(root: Path, profile: str, state: dict[str, object]) -> None:
    home = root if profile == "default" else root / "profiles" / profile
    home.mkdir(parents=True, exist_ok=True)
    (home / "gateway_state.json").write_text(
        json.dumps(state), encoding="utf-8"
    )


def configure_discord(root: Path, profile: str) -> None:
    home = root if profile == "default" else root / "profiles" / profile
    home.mkdir(parents=True, exist_ok=True)
    (home / ".env").write_text("DISCORD_BOT_TOKEN=configured\\n", encoding="utf-8")


class FakeClock:
    def __init__(self, on_sleep: Callable[[], None] | None = None) -> None:
        self.now = 0.0
        self.sleeps: list[float] = []
        self.on_sleep = on_sleep

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds
        if self.on_sleep is not None:
            self.on_sleep()


class GatewayConvergenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_converge_discovers_and_starts_every_registered_profile(self) -> None:
        manager = FakeManager(("default", "future-profile"))
        write_ready_state(self.root, "default", discord=True)
        write_ready_state(self.root, "future-profile", discord=True)

        result = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.0,
        )

        self.assertEqual(result, 0)
        self.assertEqual(
            manager.started,
            ["gateway-default", "gateway-future-profile"],
        )

    def test_converge_starts_before_polling_for_a_profile_without_prior_state(
        self,
    ) -> None:
        def write_state_when_started(service_name: str) -> None:
            self.assertEqual(service_name, "gateway-first-start")
            write_ready_state(self.root, "first-start", discord=False)

        manager = FakeManager(("first-start",), on_start=write_state_when_started)

        result = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.0,
        )

        self.assertEqual(result, 0)
        self.assertEqual(manager.started, ["gateway-first-start"])

    def test_converge_rejects_empty_registration_set(self) -> None:
        manager = FakeManager(())

        with self.assertRaisesRegex(ValueError, "no registered gateways"):
            gateway_convergence.converge(
                manager,
                self.root,
                timeout_seconds=1.0,
                poll_seconds=0.0,
            )

        self.assertEqual(manager.started, [])

    def test_converge_rejects_invalid_profile_before_lifecycle_dispatch(self) -> None:
        manager = FakeManager(("invalid/profile",))

        with self.assertRaisesRegex(ValueError, "invalid profile"):
            gateway_convergence.converge(
                manager,
                self.root,
                timeout_seconds=1.0,
                poll_seconds=0.0,
            )

        self.assertEqual(manager.started, [])

    def test_converge_waits_until_process_and_discord_are_ready(self) -> None:
        manager = FakeManager(("default",))
        manager.running["gateway-default"] = False
        configure_discord(self.root, "default")
        write_gateway_state(
            self.root,
            "default",
            {"desired_state": "running", "platforms": {"discord": {"state": "connecting"}}},
        )

        def become_ready() -> None:
            manager.running["gateway-default"] = True
            write_ready_state(self.root, "default", discord=True)

        clock = FakeClock(become_ready)
        result = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.5,
            monotonic=clock.monotonic,
            sleep=clock.sleep,
        )

        self.assertEqual(result, 0)
        self.assertEqual(clock.sleeps, [0.5])

    def test_converge_does_not_require_discord_without_a_configured_token(self) -> None:
        manager = FakeManager(("default",))
        write_gateway_state(self.root, "default", {"desired_state": "running"})

        result = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.0,
        )

        self.assertEqual(result, 0)

    def test_converge_reports_lifecycle_errors_for_all_profiles(self) -> None:
        sentinel = "DISCORD_BOT_TOKEN=sentinel-token-value"
        manager = FakeManager(
            ("default", "future-profile"),
            start_errors={
                "gateway-default": RuntimeError(sentinel),
                "gateway-future-profile": RuntimeError(sentinel),
            },
        )

        with self.assertRaisesRegex(
            RuntimeError,
            r"default=lifecycle_error, future-profile=lifecycle_error",
        ) as raised:
            gateway_convergence.converge(
                manager,
                self.root,
                timeout_seconds=1.0,
                poll_seconds=0.0,
            )

        self.assertEqual(
            manager.started,
            ["gateway-default", "gateway-future-profile"],
        )
        self.assertNotIn(sentinel, str(raised.exception))

    def test_converge_fails_immediately_for_discord_needs_attention(self) -> None:
        sentinel = "DISCORD_BOT_TOKEN=sentinel-token-value"
        manager = FakeManager(("default",))
        manager.running["gateway-default"] = False
        configure_discord(self.root, "default")
        write_gateway_state(
            self.root,
            "default",
            {
                "desired_state": "running",
                "platforms": {
                    "discord": {"state": "needs_attention", "error": sentinel}
                },
            },
        )
        clock = FakeClock()

        with self.assertRaisesRegex(
            RuntimeError, r"default=discord_needs_attention"
        ) as raised:
            gateway_convergence.converge(
                manager,
                self.root,
                timeout_seconds=1.0,
                poll_seconds=0.5,
                monotonic=clock.monotonic,
                sleep=clock.sleep,
            )

        self.assertEqual(clock.sleeps, [])
        self.assertNotIn(sentinel, str(raised.exception))

    def test_converge_times_out_with_pending_profile_names(self) -> None:
        sentinel = "DISCORD_BOT_TOKEN=sentinel-token-value"
        manager = FakeManager(("default", "future-profile"))
        manager.running["gateway-default"] = False
        write_gateway_state(self.root, "default", {"desired_state": "running"})
        write_gateway_state(
            self.root,
            "future-profile",
            {"desired_state": "stopped", "error": sentinel},
        )
        clock = FakeClock()

        with self.assertRaisesRegex(
            RuntimeError,
            r"default=process_not_running, future-profile=desired_state_not_running",
        ) as raised:
            gateway_convergence.converge(
                manager,
                self.root,
                timeout_seconds=1.0,
                poll_seconds=0.5,
                monotonic=clock.monotonic,
                sleep=clock.sleep,
            )

        self.assertEqual(clock.sleeps, [0.5, 0.5])
        self.assertNotIn(sentinel, str(raised.exception))

    def test_repeated_convergence_is_idempotent(self) -> None:
        manager = FakeManager(("default",))
        write_gateway_state(self.root, "default", {"desired_state": "running"})

        first = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.0,
        )
        second = gateway_convergence.converge(
            manager,
            self.root,
            timeout_seconds=1.0,
            poll_seconds=0.0,
        )

        self.assertEqual((first, second), (0, 0))
        self.assertEqual(manager.started, ["gateway-default", "gateway-default"])


if __name__ == "__main__":
    unittest.main()
