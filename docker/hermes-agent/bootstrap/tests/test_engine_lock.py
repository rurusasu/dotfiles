from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

import hermes_bootstrap
from hermes_bootstrap.engine_lock import EngineLock
from hermes_bootstrap.errors import RepositoryError

PACKAGE_ROOT = Path(hermes_bootstrap.__file__).resolve().parents[1]


class EngineLockTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data_root = Path(os.path.realpath(self.temp.name)) / "data"
        self.data_root.mkdir()

    @property
    def lock_path(self) -> Path:
        return self.data_root / "locks" / "bootstrap-engine.lock"

    def assert_unavailable(self) -> None:
        with self.assertRaisesRegex(
            RepositoryError, "^bootstrap engine lock is unavailable$"
        ):
            EngineLock.acquire(self.data_root)

    def test_acquires_the_canonical_lock_and_rejects_local_contention(self) -> None:
        lock = EngineLock.acquire(self.data_root)
        self.addCleanup(lock.close)

        self.assertEqual(lock.path, self.lock_path)
        lock.require_held()
        self.assert_unavailable()

    def test_rejects_unsafe_lock_objects_without_touching_external_targets(self) -> None:
        self.lock_path.parent.mkdir()
        external = self.data_root.parent / "external-lock-target"
        external.write_text("external lock marker\n", encoding="utf-8")
        external.chmod(0o644)

        cases = (
            ("symlink", lambda: self.lock_path.symlink_to(external)),
            ("directory", self.lock_path.mkdir),
            ("fifo", lambda: os.mkfifo(self.lock_path)),
            ("hardlink", lambda: os.link(external, self.lock_path)),
            (
                "wrong-mode",
                lambda: (
                    self.lock_path.write_text("private\n", encoding="utf-8"),
                    self.lock_path.chmod(0o640),
                ),
            ),
        )

        for name, create in cases:
            with self.subTest(name=name):
                create()
                self.assert_unavailable()
                self.assertEqual(
                    external.read_text(encoding="utf-8"), "external lock marker\n"
                )
                self.assertEqual(stat.S_IMODE(external.lstat().st_mode), 0o644)
                if self.lock_path.is_dir() or self.lock_path.is_symlink():
                    self.lock_path.unlink() if self.lock_path.is_symlink() else self.lock_path.rmdir()
                else:
                    self.lock_path.unlink()

    def test_rejects_a_replaced_lock_parent_without_modifying_the_external_target(
        self,
    ) -> None:
        lock = EngineLock.acquire(self.data_root)
        self.addCleanup(lock.close)
        held_locks = self.data_root / "held-locks"
        external = self.data_root.parent / "external-locks"
        external.mkdir()
        target = external / "bootstrap-engine.lock"
        target.write_text("external lock marker\n", encoding="utf-8")
        target.chmod(0o644)

        self.lock_path.parent.rename(held_locks)
        self.lock_path.parent.symlink_to(external, target_is_directory=True)

        with self.assertRaisesRegex(
            RepositoryError, "^bootstrap engine lock is unavailable$"
        ):
            lock.require_held()
        self.assertEqual(target.read_text(encoding="utf-8"), "external lock marker\n")
        self.assertEqual(stat.S_IMODE(target.lstat().st_mode), 0o644)

    def test_rejects_cross_process_contention_and_allows_reacquisition_after_close(
        self,
    ) -> None:
        ready = self.data_root / "holder-ready"
        script = (
            "import sys\n"
            "from pathlib import Path\n"
            "from hermes_bootstrap.engine_lock import EngineLock\n"
            "lock = EngineLock.acquire(Path(sys.argv[1]))\n"
            "Path(sys.argv[2]).write_text('ready', encoding='ascii')\n"
            "sys.stdin.buffer.read(1)\n"
            "lock.close()\n"
        )
        environment = {**os.environ, "PYTHONPATH": str(PACKAGE_ROOT)}
        with tempfile.TemporaryFile() as child_stderr:
            process = subprocess.Popen(
                (sys.executable, "-c", script, str(self.data_root), str(ready)),
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=child_stderr,
                env=environment,
            )

            def stderr_tail() -> str:
                child_stderr.flush()
                child_stderr.seek(0, os.SEEK_END)
                child_stderr.seek(max(0, child_stderr.tell() - 4096))
                lines = (
                    child_stderr.read()
                    .decode("utf-8", errors="replace")
                    .strip()
                    .splitlines()
                )
                return lines[-1] if lines else "<no stderr>"

            try:
                for _ in range(200):
                    if ready.exists():
                        break
                    if process.poll() is not None:
                        self.fail(
                            "lock holder exited before acquiring the lock "
                            f"(exit {process.returncode}): {stderr_tail()}"
                        )
                    time.sleep(0.01)
                else:
                    self.fail("lock holder did not acquire the lock")

                self.assert_unavailable()
            finally:
                if process.stdin is not None:
                    try:
                        process.stdin.write(b"x")
                    except BrokenPipeError:
                        pass
                    finally:
                        process.stdin.close()
                process.wait(timeout=5)

            self.assertEqual(
                process.returncode,
                0,
                "lock holder failed after acquiring the lock "
                f"(exit {process.returncode}): {stderr_tail()}",
            )

        lock = EngineLock.acquire(self.data_root)
        lock.close()
        reacquired = EngineLock.acquire(self.data_root)
        self.addCleanup(reacquired.close)
        reacquired.require_held()
