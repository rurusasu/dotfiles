"""Run the Darwin shell activation against an isolated account-command boundary."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "nix/hosts/darwin/set-default-shell.sh"


class DarwinDefaultShellTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "Darwin default-shell activation is missing")
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.shell = self.bin / "zsh"
        self.shell.write_text("#!/bin/sh\nexit 0\n")
        self.shell.chmod(0o755)
        self.accounts = self.root / "accounts.json"
        self.accounts.write_text(json.dumps({
            "alice": {"uid": "501", "shell": "/bin/bash", "home": "/Users/alice"},
            "bob": {"uid": "502", "shell": "/bin/fish", "home": "/Users/bob"},
            "root": {"uid": "0", "shell": "/bin/sh", "home": "/var/root"},
        }))
        self.shells = self.root / "shells"
        self.shells.write_text(f"/bin/bash\n{self.shell}\n")
        self.log = self.root / "changes.jsonl"
        boundary = f"#!{sys.executable}\n" + r'''
import json, os, subprocess, sys
from pathlib import Path
command = Path(sys.argv[0]).name
args = sys.argv[1:]
accounts_path = Path(os.environ["TEST_ACCOUNTS"])
accounts = json.loads(accounts_path.read_text())
if command == "id":
    if args == ["-u"]:
        print(os.environ.get("TEST_CALLER_UID", "0"))
        sys.exit(0)
    assert len(args) == 2 and args[0] == "-u", args
    if args[1] not in accounts:
        sys.exit(1)
    print(accounts[args[1]]["uid"])
elif command == "grep":
    assert args == ["-Fxq", "--", os.environ["TEST_SHELL"], "/etc/shells"], args
    sys.exit(subprocess.call([os.environ["TEST_GREP"], *args[:-1], os.environ["TEST_SHELLS"]]))
elif command == "dscl":
    assert len(args) == 4 and args[:2] == [".", "-read"] and args[3] == "UserShell", args
    assert args[2].startswith("/Users/"), args
    user = args[2][len("/Users/"):]
    if os.environ.get("TEST_READ_FAILURE") or user not in accounts:
        sys.exit(7)
    if os.environ.get("TEST_MALFORMED_READ"):
        print("unexpected output")
    else:
        print("UserShell: " + accounts[user]["shell"])
elif command == "chsh":
    assert len(args) == 5 and args[:3] == ["-l", "/Local/Default", "-s"], args
    if os.environ.get("TEST_CHANGE_FAILURE"):
        sys.exit(9)
    assert args[4] in accounts, args
    with Path(os.environ["TEST_CHANGES"]).open("a") as stream:
        stream.write(json.dumps(args) + "\n")
    if not os.environ.get("TEST_CHANGE_NOOP"):
        accounts[args[4]]["shell"] = args[3]
        accounts_path.write_text(json.dumps(accounts))
else:
    raise AssertionError(command)
'''
        for command in ("id", "grep", "dscl", "chsh"):
            path = self.bin / command
            path.write_text(boundary)
            path.chmod(0o755)
        self.environment = {
            # Keep ambient TEST_*, BASH_ENV, exported functions and Python
            # startup settings from changing what each scenario exercises.
            "PATH": str(self.bin) + os.pathsep + os.defpath,
            "HOME": str(self.root),
            "LC_ALL": "C",
            "USER": "root",
            "SUDO_USER": "bob",
            "TEST_ACCOUNTS": str(self.accounts),
            "TEST_SHELL": str(self.shell),
            "TEST_SHELLS": str(self.shells),
            "TEST_GREP": shutil.which("grep"),
            "TEST_CHANGES": str(self.log),
        }

    def run_activation(self, user="alice", **environment):
        return subprocess.run(
            ["bash", str(SCRIPT), user, str(self.shell)],
            env={**self.environment, **environment},
            capture_output=True,
            text=True,
            timeout=5,
        )

    def assert_rejected_without_changes(self, **environment):
        before = self.accounts.read_bytes()
        result = self.run_activation(**environment)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.accounts.read_bytes(), before)
        self.assertFalse(self.log.exists())

    def test_switches_only_selected_existing_user_after_install(self):
        before = json.loads(self.accounts.read_text())
        result = self.run_activation()
        self.assertEqual(result.returncode, 0, result.stderr)
        after = json.loads(self.accounts.read_text())
        expected = json.loads(json.dumps(before))
        expected["alice"]["shell"] = str(self.shell)
        self.assertEqual(after, expected)
        self.assertEqual(
            json.loads(self.log.read_text()),
            ["-l", "/Local/Default", "-s", str(self.shell), "alice"],
        )

    def test_repeated_activation_does_not_switch_again(self):
        first = self.run_activation()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.run_activation()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)

    def test_missing_shell_never_changes_account(self):
        self.shell.unlink()
        self.assert_rejected_without_changes()

    def test_non_executable_shell_never_changes_account(self):
        self.shell.chmod(0o644)
        self.assert_rejected_without_changes()

    def test_unregistered_shell_never_changes_account(self):
        self.shells.write_text("/bin/bash\n")
        self.assert_rejected_without_changes()

    def test_unknown_user_never_creates_account(self):
        self.assert_rejected_without_changes(user="missing")

    def test_root_account_is_rejected(self):
        self.assert_rejected_without_changes(user="root")

    def test_non_root_caller_is_rejected(self):
        self.assert_rejected_without_changes(TEST_CALLER_UID="501")

    def test_account_read_failure_never_changes_account(self):
        self.assert_rejected_without_changes(TEST_READ_FAILURE="1")

    def test_malformed_account_read_never_changes_account(self):
        self.assert_rejected_without_changes(TEST_MALFORMED_READ="1")

    def test_change_failure_is_reported(self):
        self.assert_rejected_without_changes(TEST_CHANGE_FAILURE="1")

    def test_unapplied_change_is_not_reported_as_success(self):
        result = self.run_activation(TEST_CHANGE_NOOP="1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(self.accounts.read_text())["alice"]["shell"], "/bin/bash")


if __name__ == "__main__":
    unittest.main()
