from __future__ import annotations

import contextlib
import errno
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from hermes_storage_seed import seed

TEST_TOKEN = "0123456789abcdef0123456789abcdef"


def _run_seed_without_source_write_access(source: Path, destination: Path) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    module_root = str(Path(__file__).resolve().parents[1])
    environment["PYTHONPATH"] = os.pathsep.join(filter(None, (module_root, environment.get("PYTHONPATH", ""))))

    def drop_root_privileges() -> None:
        if os.geteuid() != 0:
            return
        import pwd

        nobody = pwd.getpwnam("nobody")
        os.setgroups([])
        os.setgid(nobody.pw_gid)
        os.setuid(nobody.pw_uid)

    return subprocess.run(
        [
            sys.executable,
            "-c",
            "from pathlib import Path; import sys; from hermes_storage_seed import seed; "
            "seed(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])",
            str(source),
            str(destination),
            TEST_TOKEN,
        ],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        preexec_fn=drop_root_privileges,
    )


class HermesStorageSeedTests(unittest.TestCase):
    def test_skips_nested_cache_directories_with_external_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            profile_home = source / "profiles" / "nancy" / "home"
            cache = profile_home / ".cache" / "uv" / "bin"
            cache.mkdir(parents=True)
            destination.mkdir()
            (profile_home / "persistent.txt").write_text("kept\n", encoding="utf-8")
            (cache / "python").symlink_to("/nix/store/unavailable-python")

            seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / "profiles" / "nancy" / "home" / ".cache").exists())
            self.assertEqual(
                (destination / "profiles" / "nancy" / "home" / "persistent.txt").read_text(
                    encoding="utf-8"
                ),
                "kept\n",
            )

    def test_skips_nested_cache_symlink_classified_as_a_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            profile_home = source / "profiles" / "nancy" / "home"
            profile_home.mkdir(parents=True)
            destination.mkdir()
            (profile_home / ".cache").symlink_to("/opt/data/missing-cache", target_is_directory=True)

            seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / "profiles" / "nancy" / "home" / ".cache").is_symlink())

    def test_skips_entry_when_bind_mount_cannot_lstat_special_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "config.yaml").write_text("gateway: docker\n", encoding="utf-8")
            socket_path = source / "gateway.sock"
            socket_path.touch()
            original_lstat = Path.lstat

            def docker_desktop_lstat(path: Path) -> os.stat_result:
                if path == socket_path:
                    raise OSError(errno.ENOTSUP, "Operation not supported", str(path))
                return original_lstat(path)

            with mock.patch.object(Path, "lstat", docker_desktop_lstat):
                seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / "gateway.sock").exists())
            self.assertEqual((destination / "config.yaml").read_text(encoding="utf-8"), "gateway: docker\n")
            self.assertEqual(
                (destination / ".dotfiles-hermes-storage-ready-v1").read_text(encoding="utf-8"),
                f"version=1\nvolume_token={TEST_TOKEN}\n",
            )

    def test_propagates_unrelated_lstat_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            blocked_path = source / "blocked.txt"
            blocked_path.touch()
            original_lstat = Path.lstat

            def denied_lstat(path: Path) -> os.stat_result:
                if path == blocked_path:
                    raise OSError(errno.EACCES, "Permission denied", str(path))
                return original_lstat(path)

            with mock.patch.object(Path, "lstat", denied_lstat):
                with self.assertRaisesRegex(OSError, "Permission denied"):
                    seed(source, destination, TEST_TOKEN)

    def test_does_not_skip_persistent_file_when_lstat_is_unsupported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            state_database = source / "state.db"
            state_database.touch()
            original_lstat = Path.lstat

            def unsupported_lstat(path: Path) -> os.stat_result:
                if path == state_database:
                    raise OSError(errno.ENOTSUP, "Operation not supported", str(path))
                return original_lstat(path)

            with mock.patch.object(Path, "lstat", unsupported_lstat):
                with self.assertRaisesRegex(OSError, "Operation not supported"):
                    seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / ".dotfiles-hermes-storage-ready-v1").exists())

    @unittest.skipUnless(hasattr(socket, "AF_UNIX"), "requires Unix domain sockets")
    def test_skips_unix_socket_and_publishes_ready_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "config.yaml").write_text("gateway: docker\n", encoding="utf-8")
            socket_path = source / "gateway.sock"

            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as gateway:
                gateway.bind(str(socket_path))
                seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / "gateway.sock").exists())
            self.assertEqual((destination / "config.yaml").read_text(encoding="utf-8"), "gateway: docker\n")
            self.assertEqual(
                (destination / ".dotfiles-hermes-storage-ready-v1").read_text(encoding="utf-8"),
                f"version=1\nvolume_token={TEST_TOKEN}\n",
            )

    @unittest.skipUnless(hasattr(os, "mkfifo"), "requires POSIX FIFOs")
    def test_skips_nested_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            runtime = source / "runtime"
            runtime.mkdir(parents=True)
            destination.mkdir()
            (runtime / "state.txt").write_text("persistent\n", encoding="utf-8")
            os.mkfifo(runtime / "events.fifo")

            seed(source, destination, TEST_TOKEN)

            self.assertFalse((destination / "runtime" / "events.fifo").exists())
            self.assertEqual(
                (destination / "runtime" / "state.txt").read_text(encoding="utf-8"), "persistent\n"
            )

    def test_replaces_source_ready_marker_only_after_successful_seed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            marker = ".dotfiles-hermes-storage-ready-v1"
            (source / marker).write_text("spoofed\n", encoding="utf-8")
            (source / "config.yaml").write_text("gateway: docker\n", encoding="utf-8")

            seed(source, destination, TEST_TOKEN)

            self.assertEqual(
                (destination / marker).read_text(encoding="utf-8"),
                f"version=1\nvolume_token={TEST_TOKEN}\n",
            )

    @unittest.skipUnless(os.name == "posix", "requires POSIX directory permissions")
    def test_copies_clean_wal_database_from_read_only_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            database = source / "clean-wal.db"
            connection = sqlite3.connect(database)
            self.assertEqual(connection.execute("pragma journal_mode=wal").fetchone()[0], "wal")
            connection.execute("create table messages (body text)")
            connection.execute("insert into messages values ('kept')")
            connection.commit()
            connection.close()
            self.assertFalse((source / "clean-wal.db-wal").exists())
            self.assertFalse((source / "clean-wal.db-shm").exists())

            root.chmod(0o755)
            database.chmod(0o444)
            destination.chmod(0o777)
            source.chmod(0o555)
            try:
                result = _run_seed_without_source_write_access(source, destination)
            finally:
                source.chmod(0o755)
            self.assertEqual(result.returncode, 0, result.stderr)

            copied = sqlite3.connect(destination / "clean-wal.db")
            self.assertEqual(copied.execute("select body from messages").fetchone()[0], "kept")
            copied.close()

    @unittest.skipUnless(os.name == "posix", "requires POSIX directory permissions")
    def test_copies_uncheckpointed_wal_without_modifying_source_sidecars(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            database = source / "active-wal.db"
            writer = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import os, sqlite3, sys; db=sqlite3.connect(sys.argv[1]); "
                    "db.execute('pragma journal_mode=wal'); db.execute('pragma wal_autocheckpoint=0'); "
                    "db.execute('create table messages (body text)'); db.commit(); "
                    "db.execute('pragma wal_checkpoint(truncate)'); "
                    "db.execute(\"insert into messages values ('wal-only')\"); db.commit(); os._exit(0)",
                    str(database),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(writer.returncode, 0, writer.stderr)
            wal = source / "active-wal.db-wal"
            shared_memory = source / "active-wal.db-shm"
            self.assertTrue(wal.is_file())
            self.assertTrue(shared_memory.is_file())
            original_wal = wal.read_bytes()
            original_shared_memory = shared_memory.read_bytes()

            root.chmod(0o755)
            destination.chmod(0o777)
            for path in (database, wal, shared_memory):
                path.chmod(0o444)
            source.chmod(0o555)
            try:
                result = _run_seed_without_source_write_access(source, destination)
            finally:
                source.chmod(0o755)
            self.assertEqual(result.returncode, 0, result.stderr)

            copied = sqlite3.connect(destination / "active-wal.db")
            self.assertEqual(copied.execute("select body from messages").fetchone()[0], "wal-only")
            copied.close()
            self.assertEqual(wal.read_bytes(), original_wal)
            self.assertEqual(shared_memory.read_bytes(), original_shared_memory)

    @unittest.skipUnless(os.name == "posix", "requires POSIX directory permissions")
    def test_copies_uncheckpointed_wal_without_shared_memory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            database = source / "wal-without-shm.db"
            writer = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import os, sqlite3, sys; db=sqlite3.connect(sys.argv[1]); "
                    "db.execute('pragma journal_mode=wal'); db.execute('pragma wal_autocheckpoint=0'); "
                    "db.execute('create table messages (body text)'); db.commit(); "
                    "db.execute('pragma wal_checkpoint(truncate)'); "
                    "db.execute(\"insert into messages values ('wal-only')\"); db.commit(); os._exit(0)",
                    str(database),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(writer.returncode, 0, writer.stderr)
            wal = source / "wal-without-shm.db-wal"
            shared_memory = source / "wal-without-shm.db-shm"
            self.assertTrue(wal.is_file())
            self.assertTrue(shared_memory.is_file())
            shared_memory.unlink()
            original_wal = wal.read_bytes()

            root.chmod(0o755)
            destination.chmod(0o777)
            for path in (database, wal):
                path.chmod(0o444)
            source.chmod(0o555)
            try:
                result = _run_seed_without_source_write_access(source, destination)
            finally:
                source.chmod(0o755)
            self.assertEqual(result.returncode, 0, result.stderr)

            with contextlib.closing(sqlite3.connect(destination / database.name)) as copied:
                self.assertEqual(copied.execute("select body from messages").fetchone()[0], "wal-only")
            self.assertEqual(wal.read_bytes(), original_wal)
            self.assertFalse(shared_memory.exists())

    @unittest.skipUnless(os.name == "posix", "requires POSIX directory permissions")
    def test_recovers_hot_rollback_journal_without_modifying_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            database = source / "hot-journal.db"
            writer = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import os, sqlite3, sys; db=sqlite3.connect(sys.argv[1]); "
                    "db.execute('pragma journal_mode=delete'); "
                    "db.execute('create table checks (value text)'); "
                    "db.execute(\"insert into checks values ('committed')\"); db.commit(); "
                    "db.execute('begin immediate'); db.execute(\"update checks set value='uncommitted'\"); "
                    "assert os.path.exists(sys.argv[1] + '-journal'); os._exit(0)",
                    str(database),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(writer.returncode, 0, writer.stderr)
            journal = source / "hot-journal.db-journal"
            self.assertTrue(journal.is_file())
            original_database = database.read_bytes()
            original_journal = journal.read_bytes()

            root.chmod(0o755)
            destination.chmod(0o777)
            for path in (database, journal):
                path.chmod(0o444)
            source.chmod(0o555)
            try:
                result = _run_seed_without_source_write_access(source, destination)
            finally:
                source.chmod(0o755)
            self.assertEqual(result.returncode, 0, result.stderr)

            with contextlib.closing(sqlite3.connect(destination / database.name)) as copied:
                self.assertEqual(copied.execute("select value from checks").fetchone()[0], "committed")
            self.assertEqual(database.read_bytes(), original_database)
            self.assertEqual(journal.read_bytes(), original_journal)

    def test_preserves_relative_directory_symlink_within_hermes_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            skill = source / "shared" / "skills" / "green"
            profile_skills = source / "profiles" / "shiraishi" / "skills"
            skill.mkdir(parents=True)
            profile_skills.mkdir(parents=True)
            destination.mkdir()
            (skill / "SKILL.md").write_text("green\n", encoding="utf-8")
            link_target = "../../../shared/skills/green"
            (profile_skills / "green").symlink_to(link_target, target_is_directory=True)

            try:
                seed(source, destination, TEST_TOKEN)
            except ValueError as error:
                self.fail(f"safe relative symlink was rejected: {error}")

            copied_link = destination / "profiles" / "shiraishi" / "skills" / "green"
            self.assertTrue(copied_link.is_symlink())
            self.assertEqual(os.readlink(copied_link), link_target)
            self.assertEqual((copied_link / "SKILL.md").read_text(encoding="utf-8"), "green\n")

    def test_preserves_absolute_symlink_below_opt_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            link_target = "/opt/data/hindsight/models/model.bin"
            (source / "model.bin").symlink_to(link_target)

            try:
                seed(source, destination, TEST_TOKEN)
            except ValueError as error:
                self.fail(f"safe absolute symlink was rejected: {error}")

            copied_link = destination / "model.bin"
            self.assertTrue(copied_link.is_symlink())
            self.assertEqual(os.readlink(copied_link), link_target)

    def test_rejects_relative_symlink_that_escapes_hermes_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            links = source / "links"
            links.mkdir(parents=True)
            destination.mkdir()
            (root / "outside.txt").write_text("private\n", encoding="utf-8")
            (links / "outside.txt").symlink_to("../../outside.txt")

            with self.assertRaisesRegex(ValueError, "relative symlink target escapes Hermes data"):
                seed(source, destination, TEST_TOKEN)

    def test_rejects_relative_symlink_that_escapes_after_relocation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "secret.txt").write_text("private\n", encoding="utf-8")
            (source / "secret-link").symlink_to("../source/secret.txt")

            with self.assertRaisesRegex(ValueError, "relative symlink target escapes Hermes data after relocation"):
                seed(source, destination, TEST_TOKEN)

    def test_rejects_absolute_symlink_outside_opt_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "passwd").symlink_to("/etc/passwd")

            with self.assertRaisesRegex(ValueError, "absolute symlink target must be below /opt/data"):
                seed(source, destination, TEST_TOKEN)

    def test_copies_regular_files_and_sqlite_databases_without_sidecars(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "config.yaml").write_text("gateway: docker\n", encoding="utf-8")
            (source / ".op.env").write_text("OP_SERVICE_ACCOUNT_TOKEN=secret\n", encoding="utf-8")
            (source / ".xurl").mkdir()
            (source / ".xurl" / "auth.json").write_text("cache", encoding="utf-8")
            (source / ".browser").mkdir()
            (source / ".browser" / "profile").write_text("browser", encoding="utf-8")
            database = source / "state.db"
            connection = sqlite3.connect(database)
            connection.execute("create table messages (body text)")
            connection.execute("insert into messages values ('kept')")
            connection.commit()
            connection.close()
            (source / "orphan.db-wal").write_text("do not copy", encoding="utf-8")
            (source / "orphan.db-shm").write_text("do not copy", encoding="utf-8")

            seed(source, destination, TEST_TOKEN)

            self.assertEqual((destination / "config.yaml").read_text(encoding="utf-8"), "gateway: docker\n")
            self.assertFalse((destination / ".op.env").exists())
            self.assertFalse((destination / ".xurl").exists())
            self.assertFalse((destination / ".browser").exists())
            self.assertFalse((destination / "orphan.db-wal").exists())
            self.assertFalse((destination / "orphan.db-shm").exists())
            copied = sqlite3.connect(destination / "state.db")
            self.assertEqual(copied.execute("select body from messages").fetchone()[0], "kept")
            copied.close()

    def test_requires_an_empty_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (destination / "existing").write_text("keep", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "destination must be empty"):
                seed(source, destination, TEST_TOKEN)

    def test_replaces_an_incomplete_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "current").write_text("new\n", encoding="utf-8")
            (destination / "partial").write_text("old\n", encoding="utf-8")
            (destination / ".dotfiles-hermes-storage-ready-v1").symlink_to("partial")

            seed(source, destination, TEST_TOKEN, replace_incomplete=True)

            self.assertFalse((destination / "partial").exists())
            self.assertEqual((destination / "current").read_text(encoding="utf-8"), "new\n")
            self.assertFalse((destination / ".dotfiles-hermes-storage-ready-v1").is_symlink())

    def test_rejects_an_invalid_ready_token_before_clearing_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            existing = destination / "partial"
            existing.write_text("keep\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "ready token"):
                seed(source, destination, "not-a-token", replace_incomplete=True)

            self.assertEqual(existing.read_text(encoding="utf-8"), "keep\n")

    def test_copies_sqlite_database_with_uri_reserved_characters(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            database = source / "state?#%.db"
            with contextlib.closing(sqlite3.connect(database)) as connection:
                connection.execute("create table checks (value text)")
                connection.execute("insert into checks values ('reserved-name')")
                connection.commit()

            seed(source, destination, TEST_TOKEN)

            with contextlib.closing(sqlite3.connect(destination / database.name)) as copied:
                self.assertEqual(copied.execute("select value from checks").fetchone()[0], "reserved-name")


if __name__ == "__main__":
    unittest.main()
