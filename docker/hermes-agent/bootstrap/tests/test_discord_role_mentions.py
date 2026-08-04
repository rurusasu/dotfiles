"""Runtime contract for managed Discord bot-role mentions."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace


ADAPTER_PATH = Path("/opt/hermes/plugins/platforms/discord/adapter.py")
if ADAPTER_PATH.is_file():
    sys.path.insert(0, "/opt/hermes")
    from plugins.platforms.discord.adapter import DiscordAdapter
else:  # pragma: no cover - exercised only outside the runtime image
    DiscordAdapter = None  # type: ignore[assignment,misc]


class DiscordRoleMentionTests(unittest.TestCase):
    def setUp(self) -> None:
        if DiscordAdapter is None:
            self.skipTest("the Hermes runtime adapter is only available in the image")

        self.adapter = object.__new__(DiscordAdapter)
        self.adapter._client = SimpleNamespace(
            user=SimpleNamespace(id=1531304105979412581)
        )

    def test_managed_bot_role_mention_is_admitted_as_a_bot_mention(self) -> None:
        message = SimpleNamespace(
            content="<@&1531425616740487282>\nDodaの求人を処理して",
            mentions=[],
            role_mentions=[
                SimpleNamespace(
                    id=1531425616740487282,
                    tags=SimpleNamespace(bot_id=1531304105979412581),
                )
            ],
        )

        self.assertTrue(self.adapter._self_is_explicitly_mentioned(message))

    def test_unrelated_role_mention_is_not_admitted(self) -> None:
        message = SimpleNamespace(
            content="<@&999999999999999999>\nDodaの求人を処理して",
            mentions=[],
            role_mentions=[
                SimpleNamespace(
                    id=999999999999999999,
                    tags=SimpleNamespace(bot_id=999999999999999999),
                )
            ],
        )

        self.assertFalse(self.adapter._self_is_explicitly_mentioned(message))


if __name__ == "__main__":
    unittest.main()
