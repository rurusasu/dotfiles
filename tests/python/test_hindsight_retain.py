import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

REPO_ROOT = Path(__file__).resolve().parents[2]
RETAIN_PATH = REPO_ROOT / "chezmoi/dot_hindsight/codex/scripts/retain.py"
CONFIG_PATH = RETAIN_PATH.parent / "lib/config.py"
USER_CONFIG_PATH = REPO_ROOT / "chezmoi/dot_hindsight/codex.json"


def load_retain_module():
    spec = importlib.util.spec_from_file_location("hindsight_retain", RETAIN_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {RETAIN_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ChunkedRetentionTests(unittest.TestCase):
    def test_one_turn_cadence_still_chunks_and_uses_timestamp_document(self):
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


class ConfigPrecedenceTests(unittest.TestCase):
    def test_defaults_install_user_and_environment_in_order(self):
        spec = importlib.util.spec_from_file_location("hindsight_config", CONFIG_PATH)
        config = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(config)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            install = home / ".hindsight/codex"
            install.mkdir(parents=True)
            with (
                patch.object(config, "__file__", str(install / "scripts/lib/config.py")),
                patch.object(config.os.path, "expanduser", return_value=str(home)),
                patch.dict(os.environ, {}, clear=True),
            ):
                self.assertEqual(config.load_config()["retainMode"], "full-session")
                (install / "settings.json").write_text(json.dumps({"retainMode": "chunked", "retainEveryNTurns": 3}))
                self.assertEqual(config.load_config()["retainMode"], "chunked")
                (home / ".hindsight/codex.json").write_text(
                    json.dumps({"retainMode": "full-session", "retainEveryNTurns": 1, "retainOverlapTurns": None})
                )
                loaded = config.load_config()
                self.assertEqual(loaded["retainMode"], "full-session")
                self.assertEqual(loaded["retainEveryNTurns"], 1)
                self.assertEqual(loaded["retainOverlapTurns"], 2)
                with patch.dict(os.environ, {"HINDSIGHT_RETAIN_MODE": "chunked", "HINDSIGHT_AUTO_RETAIN": "false"}):
                    loaded = config.load_config()
                    self.assertEqual(loaded["retainMode"], "chunked")
                    self.assertFalse(loaded["autoRetain"])


class RetentionContractTests(unittest.TestCase):
    def run_session(self, overrides=None, turns=4, env=None):
        """Run real config, transcript, slicing and state code; capture API payloads."""
        retain = load_retain_module()
        client = Mock()
        client.retain.return_value = {}
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".hindsight").mkdir()
            shutil.copyfile(USER_CONFIG_PATH, home / ".hindsight/codex.json")
            if overrides:
                config_path = home / ".hindsight/codex.json"
                config = json.loads(config_path.read_text())
                config.update(overrides)
                config_path.write_text(json.dumps(config))
            transcript_path = home / "rollout.jsonl"
            messages = []
            with (
                patch.dict(os.environ, env or {}, clear=True),
                patch.object(os.path, "expanduser", return_value=str(home)),
                patch.object(retain, "get_api_url", return_value="http://127.0.0.1:8888"),
                patch.object(retain, "HindsightClient", return_value=client),
                patch.object(retain, "ensure_bank_mission"),
            ):
                for turn in range(1, turns + 1):
                    messages.extend(
                        [
                            {"role": "user", "content": f"question {turn}"},
                            {
                                "role": "assistant",
                                "content": [
                                    {"type": "text", "text": f"answer {turn}"},
                                    {"type": "tool_use", "name": "shell", "input": {"command": [f"task-{turn}"]}},
                                    {"type": "tool_result", "content": f"result {turn}"},
                                ],
                            },
                        ]
                    )
                    transcript_path.write_text("\n".join(json.dumps(message) for message in messages))
                    hook = json.dumps({"session_id": "session-1", "transcript_path": str(transcript_path)})
                    with (
                        patch.object(sys, "stdin", io.StringIO(hook)),
                        patch.object(retain.time, "time", return_value=turn),
                    ):
                        retain.main()
        return [call.kwargs for call in client.retain.call_args_list]

    def assert_payload_turns(self, payload, turns):
        messages = json.loads(payload["content"])
        self.assertEqual(
            [message["content"][0]["text"] for message in messages],
            [text for turn in turns for text in (f"question {turn}", f"answer {turn}")],
        )
        self.assertEqual(payload["metadata"]["message_count"], str(2 * len(turns)))
        self.assertEqual(payload["metadata"]["session_id"], "session-1")
        self.assertEqual(payload["metadata"]["managedBy"], "dotfiles")
        self.assertEqual(payload["bank_id"], "codex-shared")
        self.assertEqual(payload["tags"], ["session-1"])
        self.assertEqual(messages[-1]["content"][1]["input"], {"command": [f"task-{turns[-1]}"]})
        self.assertEqual(messages[-1]["content"][2]["content"], f"result {turns[-1]}")

    def test_distributed_chunked_config_bounds_payload_and_keeps_overlap(self):
        payloads = self.run_session()
        self.assertEqual(len(payloads), 4)
        for payload, turns in zip(payloads, ([1], [1, 2], [2, 3], [3, 4]), strict=True):
            self.assert_payload_turns(payload, turns)
        self.assertEqual(
            [payload["document_id"] for payload in payloads],
            ["session-1-1000", "session-1-2000", "session-1-3000", "session-1-4000"],
        )
        self.assertEqual(sum(int(payload["metadata"]["message_count"]) for payload in payloads), 14)

    def test_full_session_environment_override_resends_history_and_upserts_session(self):
        payloads = self.run_session(env={"HINDSIGHT_RETAIN_MODE": "full-session"})
        self.assertEqual(len(payloads), 4)
        for payload, turns in zip(payloads, ([1], [1, 2], [1, 2, 3], [1, 2, 3, 4]), strict=True):
            self.assert_payload_turns(payload, turns)
        self.assertEqual([payload["document_id"] for payload in payloads], ["session-1"] * 4)
        self.assertEqual(sum(int(payload["metadata"]["message_count"]) for payload in payloads), 20)

    def test_cadence_is_shared_but_only_chunked_adds_overlap_window(self):
        for mode, windows, documents in (
            ("chunked", ([1, 2], [2, 3, 4]), ["session-1-2000", "session-1-4000"]),
            ("full-session", ([1, 2], [1, 2, 3, 4]), ["session-1", "session-1"]),
        ):
            with self.subTest(mode=mode):
                payloads = self.run_session({"retainMode": mode, "retainEveryNTurns": 2, "retainOverlapTurns": 1})
                self.assertEqual(len(payloads), 2)
                for payload, turns in zip(payloads, windows, strict=True):
                    self.assert_payload_turns(payload, turns)
                self.assertEqual([payload["document_id"] for payload in payloads], documents)

    def test_chunked_without_overlap_retains_only_latest_turn(self):
        payloads = self.run_session({"retainOverlapTurns": 0})
        self.assertEqual(len(payloads), 4)
        for turn, payload in enumerate(payloads, 1):
            self.assert_payload_turns(payload, [turn])


if __name__ == "__main__":
    unittest.main()
