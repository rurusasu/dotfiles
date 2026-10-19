"""Process-local GitHub authentication for Hermes bootstrap."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, repr=False)
class GitAuth:
    """GitHub authentication retained only for the current bootstrap process."""

    token: str

    def __repr__(self) -> str:
        return "GitAuth(<redacted>)"
