"""Fail-closed patches for supported Hermes upstream source shapes."""

from __future__ import annotations

import re
from pathlib import Path


PatternVariant = tuple[str, str]

LEGACY_EXPLICIT_BROWSER_TOOLSET = '''\
    "browser": {
        "description": "Browser automation for web interaction (navigate, click, type, scroll, iframes, hold-click) with web search for finding URLs",
        "tools": [
            "browser_navigate", "browser_snapshot", "browser_click",
            "browser_type", "browser_scroll", "browser_back",
            "browser_press", "browser_get_images",
            "browser_vision", "browser_console", "browser_cdp",
            "browser_dialog", "web_search"
        ],
        "includes": []
    },
'''
LEGACY_EXPLICIT_BROWSER_TOOLSET_PATCHED = LEGACY_EXPLICIT_BROWSER_TOOLSET.replace(
    '            "browser_dialog", "web_search"\n',
    '            "browser_dialog"\n',
)

COMPREHENSION_BROWSER_TOOLSET = '''\
    "browser": _ts(
        "Browser automation for web interaction (navigate, click, type, scroll, "
        "iframes, hold-click) with web search for finding URLs",
        [t for t in _HERMES_CORE_TOOLS if t.startswith("browser_")] + ["web_search"],
    ),
'''
COMPREHENSION_BROWSER_TOOLSET_PATCHED = COMPREHENSION_BROWSER_TOOLSET.replace(
    ' + ["web_search"]',
    "",
)

FIXED_BROWSER_TOOLSET = '''\
    "browser": _ts(
        "Browser automation for web interaction (navigate, click, type, scroll, "
        "iframes, hold-click)",
        [t for t in _HERMES_CORE_TOOLS if t.startswith("browser_")],
    ),
'''

BROWSER_TOOLSET_VARIANTS: tuple[PatternVariant, ...] = (
    (
        re.escape(LEGACY_EXPLICIT_BROWSER_TOOLSET),
        LEGACY_EXPLICIT_BROWSER_TOOLSET_PATCHED,
    ),
    (
        re.escape(COMPREHENSION_BROWSER_TOOLSET),
        COMPREHENSION_BROWSER_TOOLSET_PATCHED,
    ),
    (re.escape(FIXED_BROWSER_TOOLSET), FIXED_BROWSER_TOOLSET),
)


def replace_pattern_variant_once(
    path: Path,
    variants: tuple[PatternVariant, ...],
) -> None:
    """Replace exactly one match across all supported source variants."""
    text = path.read_text(encoding="utf-8")
    matches = [
        (match, replacement)
        for pattern, replacement in variants
        for match in re.finditer(pattern, text)
    ]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one supported source variant in {path}")

    match, replacement = matches[0]
    updated = text[: match.start()] + replacement + text[match.end() :]
    path.write_text(updated, encoding="utf-8")
