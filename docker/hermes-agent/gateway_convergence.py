#!/usr/bin/env python3
"""Converge every Hermes profile Gateway to its desired running state."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


class GatewayManager(Protocol):
    """The service-manager operations required by the convergence command."""

    def list_profile_gateways(self) -> list[str]: ...

    def start(self, service_name: str) -> None: ...

    def is_running(self, service_name: str) -> bool: ...


class NoRegisteredGatewaysError(ValueError):
    """Raised when s6 has no registered Gateway services."""


@dataclass(frozen=True)
class GatewayTarget:
    profile: str
    service_name: str
    profile_home: Path
    discord_required: bool


_PROFILE_NAME = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")
_MAX_PROFILE_NAME_LENGTH = 251


def validate_profile_name(profile: str) -> None:
    """Use Hermes validation when available, with a test-environment fallback."""
    try:
        from hermes_cli.service_manager import validate_profile_name as validate
    except ModuleNotFoundError:
        if (
            not isinstance(profile, str)
            or len(profile) > _MAX_PROFILE_NAME_LENGTH
            or _PROFILE_NAME.fullmatch(profile) is None
        ):
            raise ValueError("invalid profile name")
        return
    validate(profile)


def profile_home(root: Path, profile: str) -> Path:
    return root if profile == "default" else root / "profiles" / profile


def discord_is_configured(home: Path) -> bool:
    env_path = home / ".env"
    if not env_path.is_file():
        return False
    for line in env_path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() == "DISCORD_BOT_TOKEN":
            return bool(value.strip())
    return False


def discover_targets(manager: GatewayManager, root: Path) -> tuple[GatewayTarget, ...]:
    profiles = tuple(manager.list_profile_gateways())
    if not profiles:
        raise NoRegisteredGatewaysError("no registered gateways")
    for profile in profiles:
        validate_profile_name(profile)
    return tuple(
        GatewayTarget(
            profile=profile,
            service_name=f"gateway-{profile}",
            profile_home=profile_home(root, profile),
            discord_required=discord_is_configured(profile_home(root, profile)),
        )
        for profile in sorted(profiles, key=lambda item: (item != "default", item))
    )


def _read_gateway_state(home: Path) -> dict[str, object] | None:
    try:
        state = json.loads((home / "gateway_state.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return state if isinstance(state, dict) else None


def gateway_ready(manager: GatewayManager, target: GatewayTarget) -> tuple[bool, str]:
    """Return Gateway readiness with a redacted, stable status label."""
    try:
        process_status = "ready" if manager.is_running(target.service_name) else "process_not_running"
    except Exception:
        process_status = "process_status_unavailable"

    state = _read_gateway_state(target.profile_home)
    if target.discord_required and isinstance(state, dict):
        platforms = state.get("platforms")
        discord = platforms.get("discord") if isinstance(platforms, dict) else None
        discord_state = discord.get("state") if isinstance(discord, dict) else None
        if discord_state == "needs_attention":
            return False, "discord_needs_attention"
    if process_status != "ready":
        return False, process_status
    if state is None:
        return False, "state_unavailable"
    if state.get("desired_state") != "running":
        return False, "desired_state_not_running"
    if not target.discord_required:
        return True, "ready"

    platforms = state.get("platforms")
    discord = platforms.get("discord") if isinstance(platforms, dict) else None
    discord_state = discord.get("state") if isinstance(discord, dict) else None
    if discord_state != "connected":
        return False, "discord_not_connected"
    return True, "ready"


def _raise_convergence_error(prefix: str, statuses: dict[str, str]) -> None:
    summary = ", ".join(f"{profile}={status}" for profile, status in statuses.items())
    raise RuntimeError(f"{prefix}: {summary}")


def converge(
    manager: GatewayManager,
    root: Path,
    *,
    timeout_seconds: float,
    poll_seconds: float,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> int:
    """Start each Gateway and wait until every registered profile is ready."""
    if not math.isfinite(timeout_seconds) or timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be a finite positive number")
    if not math.isfinite(poll_seconds) or poll_seconds < 0:
        raise ValueError("poll_seconds must be a finite non-negative number")

    try:
        targets = discover_targets(manager, root)
    except NoRegisteredGatewaysError:
        raise
    except Exception as error:
        raise RuntimeError("gateway discovery failed") from error
    lifecycle_failures: dict[str, str] = {}
    for target in targets:
        try:
            manager.start(target.service_name)
        except Exception:
            lifecycle_failures[target.profile] = "lifecycle_error"
    if lifecycle_failures:
        _raise_convergence_error("gateway lifecycle failed", lifecycle_failures)

    deadline = monotonic() + timeout_seconds
    while True:
        pending: dict[str, str] = {}
        for target in targets:
            ready, status = gateway_ready(manager, target)
            if not ready:
                pending[target.profile] = status
        if not pending:
            return 0
        if any(status == "discord_needs_attention" for status in pending.values()):
            _raise_convergence_error("gateway needs attention", pending)
        now = monotonic()
        if now >= deadline:
            _raise_convergence_error("gateway convergence timed out", pending)
        sleep(min(poll_seconds, deadline - now))


def _positive_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive number") from error
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return parsed


def main(argv: Sequence[str] | None = None) -> int:
    """Run convergence against the in-container s6 service manager."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=_positive_float, default=60.0)
    parser.add_argument("--poll-seconds", type=_positive_float, default=1.0)
    arguments = parser.parse_args(argv)

    try:
        from hermes_cli.service_manager import get_service_manager

        manager = get_service_manager()
    except Exception:
        print("Hermes service manager is unavailable", file=sys.stderr)
        return 2
    if getattr(manager, "kind", None) != "s6":
        print("Hermes Gateway convergence requires the s6 service manager", file=sys.stderr)
        return 2

    try:
        return converge(
            manager,
            Path(os.environ.get("HERMES_HOME", "/opt/data")),
            timeout_seconds=arguments.timeout_seconds,
            poll_seconds=arguments.poll_seconds,
        )
    except (RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
