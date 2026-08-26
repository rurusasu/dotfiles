import importlib.util
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[2]
RETAIN_PATH = REPO_ROOT / "chezmoi/dot_hindsight/codex/scripts/retain.py"


def load_retain_module():
    spec = importlib.util.spec_from_file_location("hindsight_retain", RETAIN_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {RETAIN_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ChunkedRetentionTests(unittest.TestCase):
    def test_one_turn_cadence_still_chunks_and_uses_unique_document(self):
        retain = load_retain_module()
        messages = [
            {"role": "user", "content": "old"},
            {"role": "assistant", "content": "old reply"},
            {"role": "user", "content": "latest"},
            {"role": "assistant", "content": "latest reply"},
        ]
        sliced = messages[-2:]
        client = Mock()
        client.retain.return_value = {}
        config = {
            "autoRetain": True,
            "retainMode": "chunked",
            "retainEveryNTurns": 1,
            "retainOverlapTurns": 0,
            "retainRoles": ["user", "assistant"],
        }

        with (
            patch.object(retain, "load_config", return_value=config),
            patch.object(retain, "read_transcript", return_value=messages),
            patch.object(retain, "slice_last_turns_by_user_boundary", return_value=sliced) as slice_turns,
            patch.object(retain, "prepare_retention_transcript", return_value=("latest transcript", 2)) as prepare,
            patch.object(retain, "get_api_url", return_value="http://127.0.0.1:8888"),
            patch.object(retain, "HindsightClient", return_value=client),
            patch.object(retain, "derive_bank_id", return_value="codex-bank"),
            patch.object(retain, "ensure_bank_mission"),
            patch.object(retain.time, "time", return_value=1234.5),
            patch.object(sys, "stdin", io.StringIO('{"session_id":"session-1","transcript_path":"transcript.jsonl"}')),
        ):
            retain.main()

        slice_turns.assert_called_once_with(messages, 1)
        self.assertIs(prepare.call_args.args[0], sliced)
        client.retain.assert_called_once()
        self.assertEqual(client.retain.call_args.kwargs["document_id"], "session-1-1234500")


if __name__ == "__main__":
    unittest.main()
