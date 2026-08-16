#!/opt/hermes/.venv/bin/python
"""Deterministic and live acceptance checks for Hermes Hindsight memory."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import secrets
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Iterator, Sequence
from contextlib import ExitStack, contextmanager
from pathlib import Path
from typing import Any

PROFILES = ("default", "rick", "hoffman", "risarisa", "nancy", "kuroda", "shiraishi")
REQUIRED_MODELS = ("qwen3.6:35b", "qwen3-embedding:0.6b")
RETAIN_MISSION = (
    "Capture durable dates, corrections, preferences, entities, and decisions."
)
STRICT_PROBE_PAYLOAD: dict[str, Any] = {
    "content": "Alice moved to Berlin in 2021 and works as a nurse.",
    "retain_mission": RETAIN_MISSION,
    "retain_chunk_size": 4000,
}
CORPUS: tuple[dict[str, str], ...] = (
    {
        "language": "en",
        "category": "dates",
        "content": "Alice moved to Berlin in 2021 and works as a nurse.",
    },
    {
        "language": "ja",
        "category": "dates",
        "content": "健太は2024年4月3日に札幌へ引っ越しました。",
    },
    {
        "language": "en",
        "category": "corrections",
        "content": "Correction: the launch is June 12, not June 21.",
    },
    {
        "language": "ja",
        "category": "corrections",
        "content": "訂正です。会議は火曜日ではなく水曜日です。",
    },
    {
        "language": "en",
        "category": "preferences",
        "content": "Maya prefers dark roast coffee without sugar.",
    },
    {
        "language": "ja",
        "category": "preferences",
        "content": "由美は朝の連絡をメールで受け取るのを好みます。",
    },
    {
        "language": "en",
        "category": "entities",
        "content": "Northwind Labs opened an office in Toronto.",
    },
    {
        "language": "ja",
        "category": "entities",
        "content": "青空商事は京都に新しい研究所を開設しました。",
    },
    {
        "language": "en",
        "category": "relationships",
        "content": "Priya mentors Daniel on the Atlas project.",
    },
    {
        "language": "ja",
        "category": "relationships",
        "content": "佐藤さんは鈴木さんのプロジェクト責任者です。",
    },
    {
        "language": "en",
        "category": "decisions",
        "content": "The team decided to use PostgreSQL for the archive.",
    },
    {
        "language": "ja",
        "category": "decisions",
        "content": "チームは次期版を9月に公開すると決定しました。",
    },
    {
        "language": "en",
        "category": "dates",
        "content": "Noah joined Contoso on February 14, 2022.",
    },
    {
        "language": "ja",
        "category": "corrections",
        "content": "住所は大阪市北区ではなく中央区が正しいです。",
    },
    {
        "language": "en",
        "category": "preferences",
        "content": "Elena wants reports delivered as PDF files.",
    },
    {
        "language": "ja",
        "category": "entities",
        "content": "田中葵は富士見病院で薬剤師として働いています。",
    },
    {
        "language": "en",
        "category": "relationships",
        "content": "Orion is a subsidiary of Vega Holdings.",
    },
    {
        "language": "ja",
        "category": "decisions",
        "content": "運営委員会は新しい拠点を福岡に置くことを決めました。",
    },
    {
        "language": "en",
        "category": "dates",
        "content": "The service contract expires on December 31, 2027.",
    },
    {
        "language": "ja",
        "category": "preferences",
        "content": "美咲は辛くない料理を選びます。",
    },
)

_BANK_RE = re.compile(
    r"^test-hermes-(default|rick|hoffman|risarisa|nancy|kuroda|shiraishi)-[0-9a-f]+$"
)
_HEX_RE = re.compile(r"^[0-9a-f]+$")


class AcceptanceError(RuntimeError):
    """A failed acceptance invariant."""


class HttpClient:
    """Small JSON HTTP client with one propagated request timeout."""

    def __init__(self, base_url: str, timeout: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def request(
        self, method: str, path: str, payload: dict[str, Any] | None = None
    ) -> tuple[int, dict[str, Any]]:
        body = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=body, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                status = response.status
                raw = response.read()
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            status = exc.code
        except (OSError, TimeoutError) as exc:
            raise AcceptanceError(f"{method} {path} failed: {exc}") from exc
        if not raw:
            return status, {}
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise AcceptanceError(f"{method} {path} returned invalid JSON") from exc
        if not isinstance(decoded, dict):
            raise AcceptanceError(
                f"{method} {path} returned a non-object JSON response"
            )
        return status, decoded


HttpFactory = Callable[[str, float], HttpClient]
ProviderFactory = Callable[[], Any]
Clock = Callable[[], float]
Sleeper = Callable[[float], None]
TokenHex = Callable[[int], str]


def nearest_rank(values: Sequence[float], percentile: int) -> float | None:
    """Return a sorted nearest-rank percentile, or None for no samples."""
    if not values:
        return None
    if percentile < 1 or percentile > 100:
        raise ValueError("percentile must be between 1 and 100")
    ordered = sorted(float(value) for value in values)
    index = math.ceil((percentile / 100) * len(ordered)) - 1
    return ordered[index]


def _default_provider_factory() -> Any:
    from plugins.memory.hindsight import HindsightMemoryProvider

    return HindsightMemoryProvider()


def _provider_config(api_url: str, run_id: str, timeout: float) -> dict[str, Any]:
    return {
        "mode": "local_external",
        "api_url": api_url,
        "bank_id": "acceptance-resolver-fallback-must-not-be-used",
        "bank_id_template": f"test-hermes-{{profile}}-{run_id}",
        "bank_retain_mission": RETAIN_MISSION,
        "memory_mode": "hybrid",
        "auto_recall": True,
        "recall_sync": True,
        "recall_types": "world,experience,opinion,observation",
        "auto_retain": True,
        "retain_async": False,
        "retain_every_n_turns": 1,
        "retain_source": "hermes-acceptance",
        "timeout": timeout,
    }


@contextmanager
def _resolved_provider(
    *,
    profile: str,
    run_id: str,
    api_url: str,
    timeout: float,
    provider_factory: ProviderFactory | None,
) -> Iterator[tuple[Any, str]]:
    if profile not in PROFILES:
        raise AcceptanceError(f"Unsupported Hermes profile: {profile}")
    if not _HEX_RE.fullmatch(run_id):
        raise AcceptanceError(
            "Acceptance run ID must contain lowercase hexadecimal characters only"
        )
    expected_bank = f"test-hermes-{profile}-{run_id}"
    old_home = os.environ.get("HERMES_HOME")
    with tempfile.TemporaryDirectory(prefix="hermes-hindsight-", dir="/tmp") as home:
        config_dir = Path(home) / "hindsight"
        config_dir.mkdir(mode=0o700)
        config_path = config_dir / "config.json"
        _write_json(config_path, _provider_config(api_url, run_id, timeout), mode=0o600)
        os.environ["HERMES_HOME"] = home
        provider = None
        try:
            provider = (provider_factory or _default_provider_factory)()
            provider.initialize(
                f"acceptance-{run_id}-{profile}",
                agent_identity=profile,
                platform="cli",
            )
            prompt = provider.system_prompt_block()
            if f"Bank: {expected_bank}," not in prompt:
                raise AcceptanceError(
                    f"Bundled provider resolver did not expose exact bank {expected_bank!r}"
                )
            yield provider, expected_bank
        finally:
            try:
                if provider is not None:
                    provider.shutdown()
            finally:
                if old_home is None:
                    os.environ.pop("HERMES_HOME", None)
                else:
                    os.environ["HERMES_HOME"] = old_home


def _write_json(path: Path, payload: dict[str, Any], *, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, mode)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        temporary_path.unlink(missing_ok=True)
        raise


def _read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AcceptanceError(f"Unable to read {label}: {path}") from exc
    if not isinstance(payload, dict):
        raise AcceptanceError(f"{label} must contain a JSON object")
    return payload


def _validate_state(state: dict[str, Any]) -> None:
    if set(state) != {"run_id", "banks", "sentinels", "timings"}:
        raise AcceptanceError("Acceptance state has unexpected or missing fields")
    run_id = state["run_id"]
    if not isinstance(run_id, str) or not _HEX_RE.fullmatch(run_id):
        raise AcceptanceError("Acceptance state has an invalid run ID")
    for key in ("banks", "sentinels"):
        value = state[key]
        if not isinstance(value, dict) or set(value) != set(PROFILES):
            raise AcceptanceError(
                f"Acceptance state {key} must contain all seven profiles"
            )
        if not all(isinstance(item, str) and item for item in value.values()):
            raise AcceptanceError(f"Acceptance state {key} contains an invalid value")
    timings = state["timings"]
    if not isinstance(timings, dict) or set(timings) != {"retain", "recall"}:
        raise AcceptanceError("Acceptance state timings must contain retain and recall")
    if not all(
        isinstance(samples, list)
        and all(isinstance(sample, (int, float)) and sample >= 0 for sample in samples)
        for samples in timings.values()
    ):
        raise AcceptanceError("Acceptance state contains invalid timing samples")


def _require_status(status: int, expected: int, operation: str) -> None:
    if status != expected:
        raise AcceptanceError(
            f"{operation} returned HTTP {status}, expected {expected}"
        )


def _validate_extract_response(
    status: int, payload: dict[str, Any], probe: int
) -> None:
    _require_status(status, 200, f"Strict extraction probe {probe}")
    facts = payload.get("facts")
    if not isinstance(facts, list) or not facts:
        raise AcceptanceError(f"Strict extraction probe {probe} returned no facts")
    for index, fact in enumerate(facts, start=1):
        if not isinstance(fact, dict):
            raise AcceptanceError(
                f"Strict extraction probe {probe} fact {index} is not an object"
            )
        for field in ("text", "fact_type", "entities"):
            if field not in fact:
                raise AcceptanceError(
                    f"Strict extraction probe {probe} fact {index} is missing {field}"
                )
        if not isinstance(fact["text"], str) or not fact["text"]:
            raise AcceptanceError(
                f"Strict extraction probe {probe} fact {index} has invalid text"
            )
        if fact["fact_type"] not in {"world", "experience"}:
            raise AcceptanceError(
                f"Strict extraction probe {probe} fact {index} has invalid fact_type"
            )
        if not isinstance(fact["entities"], list):
            raise AcceptanceError(
                f"Strict extraction probe {probe} fact {index} has invalid entities"
            )
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        raise AcceptanceError(f"Strict extraction probe {probe} is missing usage")
    for field in ("input_tokens", "output_tokens", "total_tokens"):
        if not isinstance(usage.get(field), int) or usage[field] < 0:
            raise AcceptanceError(
                f"Strict extraction probe {probe} has invalid usage.{field}"
            )


def _tool_payload(raw: str, operation: str) -> dict[str, Any]:
    try:
        payload = json.loads(raw)
    except (TypeError, json.JSONDecodeError) as exc:
        raise AcceptanceError(f"Provider {operation} returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise AcceptanceError(f"Provider {operation} returned a non-object result")
    return payload


def _require_tool_success(raw: str, operation: str, profile: str) -> str:
    payload = _tool_payload(raw, operation)
    result = payload.get("result")
    if payload.get("error") or not isinstance(result, str):
        raise AcceptanceError(f"Provider {operation} failed for profile {profile}")
    return result


def _require_tool_failure(raw: str, operation: str) -> None:
    payload = _tool_payload(raw, operation)
    text = " ".join(str(value) for value in payload.values()).lower()
    if not payload.get("error") and "failed" not in text and "error" not in text:
        raise AcceptanceError(f"Degraded {operation} was reported as successful")
    if "success" in text and not payload.get("error"):
        raise AcceptanceError(f"Degraded {operation} was reported as successful")


def _timed_tool_call(
    provider: Any,
    tool_name: str,
    arguments: dict[str, Any],
    *,
    clock: Clock,
) -> tuple[str, float]:
    started = clock()
    result = provider.handle_tool_call(tool_name, arguments)
    elapsed = max(0.0, clock() - started)
    return result, elapsed


def _recall_own_sentinel(
    provider: Any,
    *,
    profile: str,
    sentinel: str,
    timeout: float,
    clock: Clock,
    sleeper: Sleeper,
    timings: list[float],
) -> None:
    deadline = clock() + timeout
    while True:
        raw, elapsed = _timed_tool_call(
            provider,
            "hindsight_recall",
            {"query": sentinel},
            clock=clock,
        )
        timings.append(elapsed)
        result = _require_tool_success(raw, "recall", profile)
        if sentinel in result:
            return
        if clock() >= deadline:
            raise AcceptanceError(
                f"Own sentinel recall timed out for profile {profile}"
            )
        sleeper(min(1.0, timeout))


def _assert_cross_profile_isolation(
    providers: dict[str, Any],
    sentinels: dict[str, str],
    *,
    clock: Clock,
    timings: list[float],
) -> int:
    checks = 0
    for profile in PROFILES:
        provider = providers[profile]
        for other_profile in PROFILES:
            if other_profile == profile:
                continue
            sentinel = sentinels[other_profile]
            raw, elapsed = _timed_tool_call(
                provider,
                "hindsight_recall",
                {"query": sentinel},
                clock=clock,
            )
            timings.append(elapsed)
            result = _require_tool_success(raw, "recall", profile)
            if sentinel in result:
                raise AcceptanceError(
                    f"cross-profile sentinel leaked from {other_profile} into {profile}"
                )
            checks += 1
    if checks != 42:
        raise AcceptanceError(f"Expected 42 cross-profile checks, completed {checks}")
    return checks


def run_probe(
    *,
    api_url: str,
    ollama_url: str,
    strict_probes: int,
    timeout: float,
    evidence_path: Path,
    http_factory: HttpFactory = HttpClient,
    provider_factory: ProviderFactory | None = None,
    token_hex: TokenHex = secrets.token_hex,
) -> None:
    if strict_probes != 20:
        raise AcceptanceError("Strict extraction acceptance requires exactly 20 probes")
    api = http_factory(api_url, timeout)
    status, health = api.request("GET", "/health")
    _require_status(status, 200, "Hindsight health")
    if health.get("status") != "healthy" or health.get("database") != "connected":
        raise AcceptanceError(
            "Hindsight health must report healthy with a connected database"
        )

    ollama = http_factory(ollama_url, timeout)
    status, inventory = ollama.request("GET", "/api/tags")
    _require_status(status, 200, "Ollama model inventory")
    models = inventory.get("models")
    names = (
        {
            item.get("name")
            for item in models
            if isinstance(item, dict) and isinstance(item.get("name"), str)
        }
        if isinstance(models, list)
        else set()
    )
    missing = [model for model in REQUIRED_MODELS if model not in names]
    if missing:
        raise AcceptanceError(
            f"Ollama model inventory is missing: {', '.join(missing)}"
        )

    run_id = token_hex(16)
    probe_timings: list[float] = []
    with _resolved_provider(
        profile="default",
        run_id=run_id,
        api_url=api_url,
        timeout=timeout,
        provider_factory=provider_factory,
    ) as (_, bank_id):
        for index, corpus_item in enumerate(CORPUS, start=1):
            started = time.monotonic()
            payload = dict(STRICT_PROBE_PAYLOAD)
            payload["content"] = corpus_item["content"]
            status, result = api.request(
                "POST",
                f"/v1/default/banks/{bank_id}/memories/dry-run-extract",
                payload,
            )
            probe_timings.append(max(0.0, time.monotonic() - started))
            _validate_extract_response(status, result, index)

    evidence = (
        _read_json(evidence_path, "acceptance evidence")
        if evidence_path.exists()
        else {}
    )
    evidence["probe"] = {
        "strict_probes": strict_probes,
        "languages": ["en", "ja"],
        "categories": sorted({item["category"] for item in CORPUS}),
        "models": list(REQUIRED_MODELS),
        "latency_seconds": probe_timings,
    }
    _write_json(evidence_path, evidence)


def run_seed(
    *,
    api_url: str,
    profiles: Sequence[str],
    timeout: float,
    state_path: Path,
    provider_factory: ProviderFactory | None = None,
    clock: Clock = time.monotonic,
    sleeper: Sleeper = time.sleep,
    token_hex: TokenHex = secrets.token_hex,
) -> None:
    if tuple(profiles) != PROFILES:
        raise AcceptanceError(
            "Seed requires all seven managed profiles in canonical order"
        )
    run_id = token_hex(16)
    sentinels = {
        profile: f"hermes-memory-sentinel-{profile}-{token_hex(16)}"
        for profile in PROFILES
    }
    state: dict[str, Any] = {
        "run_id": run_id,
        "banks": {},
        "sentinels": sentinels,
        "timings": {"retain": [], "recall": []},
    }
    _write_json(state_path, state)

    with ExitStack() as stack:
        providers: dict[str, Any] = {}
        for profile in PROFILES:
            provider, bank_id = stack.enter_context(
                _resolved_provider(
                    profile=profile,
                    run_id=run_id,
                    api_url=api_url,
                    timeout=timeout,
                    provider_factory=provider_factory,
                )
            )
            providers[profile] = provider
            state["banks"][profile] = bank_id
            _write_json(state_path, state)

        for profile in PROFILES:
            raw, elapsed = _timed_tool_call(
                providers[profile],
                "hindsight_retain",
                {
                    "content": (
                        "For Hermes acceptance, the durable memory token assigned to "
                        f"profile {profile} is {sentinels[profile]}."
                    ),
                    "context": "Hermes acceptance sentinel",
                },
                clock=clock,
            )
            state["timings"]["retain"].append(elapsed)
            result = _require_tool_success(raw, "retain", profile)
            if "stored successfully" not in result.lower():
                raise AcceptanceError(f"Provider retain failed for profile {profile}")
            _write_json(state_path, state)

        for profile in PROFILES:
            _recall_own_sentinel(
                providers[profile],
                profile=profile,
                sentinel=sentinels[profile],
                timeout=timeout,
                clock=clock,
                sleeper=sleeper,
                timings=state["timings"]["recall"],
            )
            _write_json(state_path, state)
        _assert_cross_profile_isolation(
            providers,
            sentinels,
            clock=clock,
            timings=state["timings"]["recall"],
        )
        _write_json(state_path, state)


def run_verify(
    *,
    api_url: str,
    timeout: float,
    state_path: Path,
    evidence_path: Path,
    provider_factory: ProviderFactory | None = None,
    clock: Clock = time.monotonic,
    sleeper: Sleeper = time.sleep,
) -> None:
    state = _read_json(state_path, "acceptance state")
    _validate_state(state)
    with ExitStack() as stack:
        providers: dict[str, Any] = {}
        for profile in PROFILES:
            provider, bank_id = stack.enter_context(
                _resolved_provider(
                    profile=profile,
                    run_id=state["run_id"],
                    api_url=api_url,
                    timeout=timeout,
                    provider_factory=provider_factory,
                )
            )
            if bank_id != state["banks"][profile]:
                raise AcceptanceError(
                    f"Persisted bank does not match provider resolver for {profile}"
                )
            providers[profile] = provider

        for profile in PROFILES:
            _recall_own_sentinel(
                providers[profile],
                profile=profile,
                sentinel=state["sentinels"][profile],
                timeout=timeout,
                clock=clock,
                sleeper=sleeper,
                timings=state["timings"]["recall"],
            )
        negative_checks = _assert_cross_profile_isolation(
            providers,
            state["sentinels"],
            clock=clock,
            timings=state["timings"]["recall"],
        )

    _write_json(state_path, state)
    evidence = (
        _read_json(evidence_path, "acceptance evidence")
        if evidence_path.exists()
        else {}
    )
    evidence.update(
        {
            "status": "passed",
            "run_id": state["run_id"],
            "banks": state["banks"],
            "isolation": {
                "profiles": len(PROFILES),
                "own_sentinel_recalls": len(PROFILES),
                "seed_cross_profile_negatives": 42,
                "verify_cross_profile_negatives": negative_checks,
            },
            "latency_seconds": {
                operation: {
                    "samples": state["timings"][operation],
                    "p50": nearest_rank(state["timings"][operation], 50),
                    "p95": nearest_rank(state["timings"][operation], 95),
                }
                for operation in ("retain", "recall")
            },
        }
    )
    _write_json(evidence_path, evidence)


def run_degraded(
    *,
    api_url: str,
    timeout: float,
    state_path: Path,
    provider_factory: ProviderFactory | None = None,
    clock: Clock = time.monotonic,
) -> None:
    state = _read_json(state_path, "acceptance state")
    _validate_state(state)
    with _resolved_provider(
        profile="default",
        run_id=state["run_id"],
        api_url=api_url,
        timeout=timeout,
        provider_factory=provider_factory,
    ) as (provider, bank_id):
        if bank_id != state["banks"]["default"]:
            raise AcceptanceError(
                "Persisted default bank does not match provider resolver"
            )
        if provider.prefetch("degraded acceptance recall", session_id="degraded"):
            raise AcceptanceError(
                "Degraded prefetch injected memory while Hindsight was unavailable"
            )
        started = clock()
        try:
            provider.sync_turn(
                "degraded acceptance user turn",
                "degraded acceptance assistant turn",
                session_id="degraded",
            )
        except Exception as exc:
            raise AcceptanceError("Degraded sync_turn raised an exception") from exc
        if max(0.0, clock() - started) > timeout:
            raise AcceptanceError("Degraded sync_turn exceeded its configured timeout")
        retain = provider.handle_tool_call(
            "hindsight_retain", {"content": "degraded explicit retain must fail"}
        )
        recall = provider.handle_tool_call(
            "hindsight_recall", {"query": "degraded explicit recall must fail"}
        )
        _require_tool_failure(retain, "retain")
        _require_tool_failure(recall, "recall")


def run_cleanup(
    *,
    api_url: str,
    state_path: Path,
    timeout: float = 300,
    http_factory: HttpFactory = HttpClient,
) -> None:
    state = _read_json(state_path, "acceptance state")
    _validate_state(state)
    run_id = state["run_id"]
    for profile in PROFILES:
        bank_id = state["banks"][profile]
        expected = f"test-hermes-{profile}-{run_id}"
        if bank_id != expected or not _BANK_RE.fullmatch(bank_id):
            raise AcceptanceError(f"Refusing unsafe test bank cleanup: {bank_id}")
    if len(set(state["banks"].values())) != len(PROFILES):
        raise AcceptanceError("Refusing cleanup because test bank IDs are not unique")

    api = http_factory(api_url, timeout)
    for profile in PROFILES:
        bank_id = state["banks"][profile]
        status, _ = api.request("DELETE", f"/v1/default/banks/{bank_id}")
        if status not in {200, 202, 204, 404}:
            raise AcceptanceError(f"Bank cleanup failed for {bank_id}: HTTP {status}")
    state_path.unlink()


def _profiles(value: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in value.split(",") if item.strip())


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe = subparsers.add_parser("probe")
    probe.add_argument("--api-url", default="http://hindsight:8888")
    probe.add_argument("--ollama-url", default="http://host.docker.internal:11434")
    probe.add_argument("--strict-probes", type=int, default=20)
    probe.add_argument("--timeout", type=float, default=300)
    probe.add_argument(
        "--evidence", type=Path, default=Path("/opt/data/hindsight/acceptance.json")
    )

    seed = subparsers.add_parser("seed")
    seed.add_argument("--api-url", default="http://hindsight:8888")
    seed.add_argument("--profiles", type=_profiles, default=PROFILES)
    seed.add_argument("--timeout", type=float, default=300)
    seed.add_argument(
        "--state", type=Path, default=Path("/opt/data/hindsight/acceptance-state.json")
    )

    verify = subparsers.add_parser("verify")
    verify.add_argument("--api-url", default="http://hindsight:8888")
    verify.add_argument("--timeout", type=float, default=300)
    verify.add_argument(
        "--state", type=Path, default=Path("/opt/data/hindsight/acceptance-state.json")
    )
    verify.add_argument(
        "--evidence", type=Path, default=Path("/opt/data/hindsight/acceptance.json")
    )

    degraded = subparsers.add_parser("degraded")
    degraded.add_argument("--api-url", default="http://hindsight:8888")
    degraded.add_argument("--timeout", type=float, default=5)
    degraded.add_argument(
        "--state", type=Path, default=Path("/opt/data/hindsight/acceptance-state.json")
    )

    cleanup = subparsers.add_parser("cleanup")
    cleanup.add_argument("--api-url", default="http://hindsight:8888")
    cleanup.add_argument(
        "--state", type=Path, default=Path("/opt/data/hindsight/acceptance-state.json")
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "probe":
            run_probe(
                api_url=args.api_url,
                ollama_url=args.ollama_url,
                strict_probes=args.strict_probes,
                timeout=args.timeout,
                evidence_path=args.evidence,
            )
        elif args.command == "seed":
            run_seed(
                api_url=args.api_url,
                profiles=args.profiles,
                timeout=args.timeout,
                state_path=args.state,
            )
        elif args.command == "verify":
            run_verify(
                api_url=args.api_url,
                timeout=args.timeout,
                state_path=args.state,
                evidence_path=args.evidence,
            )
        elif args.command == "degraded":
            run_degraded(
                api_url=args.api_url,
                timeout=args.timeout,
                state_path=args.state,
            )
        elif args.command == "cleanup":
            run_cleanup(api_url=args.api_url, state_path=args.state)
        else:
            raise AcceptanceError(f"Unsupported acceptance command: {args.command}")
    except (AcceptanceError, ValueError) as exc:
        print(f"Hermes Hindsight acceptance failed: {exc}", file=sys.stderr)
        return 1
    print(f"Hermes Hindsight acceptance {args.command} passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
