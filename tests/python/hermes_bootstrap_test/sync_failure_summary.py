"""Bounded, allowlisted diagnostics for the profile-sync test fixture only."""

from __future__ import annotations


_REDACTED = "REDACTED"
_PROFILES = ("rick", "hoffman", "risarisa", "nancy", "kuroda", "shiraishi")
_STATUSES = ("changed", "unchanged", "failed")
_CATEGORIES = (
    "aggregate_preflight_blocked", "cleanup_failed", "credentials_unavailable",
    "deletion_limit_exceeded", "dry_run", "empty_owned_directory",
    "invalid_local_profile", "invalid_manifest", "invalid_profile_target",
    "local_profile_changed", "lock_busy", "missing_profile", "published",
    "push_race_exhausted", "push_rejected", "repository", "resource_limit", "unchanged",
)


def _dictionary(value: object) -> dict[str, object]:
    # Exact built-in types avoid invoking an untrusted mapping/key protocol.
    if (
        type(value) is dict
        and len(value) <= 16
        and all(type(key) is str for key in value)
    ):
        return value
    return {}


def _allowed(value: object, choices: tuple[str, ...]) -> str:
    if type(value) is str and len(value) <= 32 and value in choices:
        return value
    return _REDACTED


def initial_sync_summary(exit_code: object, payload: object) -> str:
    """Return fixed fixture fields; never render raw reports or write streams."""

    code = str(exit_code) if type(exit_code) is int and 0 <= exit_code <= 8 else _REDACTED
    report = _dictionary(payload)
    status = _allowed(report.get("status"), _STATUSES)
    values = {name: (_REDACTED, _REDACTED) for name in _PROFILES}
    entries = report.get("profiles")
    seen: set[str] = set()
    if type(entries) is list and len(entries) <= len(_PROFILES):
        for entry in entries:
            fields = _dictionary(entry)
            name = _allowed(fields.get("name"), _PROFILES)
            if name not in values:
                continue
            values[name] = (
                (_REDACTED, _REDACTED)
                if name in seen
                else (
                    _allowed(fields.get("status"), _STATUSES),
                    _allowed(fields.get("category"), _CATEGORIES),
                )
            )
            seen.add(name)
    profiles = ";".join(
        f"{name}={state}/{category}"
        for name, (state, category) in values.items()
    )
    return f"initial-sync exit={code} status={status} profiles=[{profiles}]"
