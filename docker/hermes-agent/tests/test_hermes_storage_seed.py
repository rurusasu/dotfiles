from __future__ import annotations

import os
import sqlite3
import tempfile
import unittest
from pathlib import Path

from hermes_storage_seed import seed


class HermesStorageSeedTests(unittest.TestCase):
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

            source.chmod(0o555)
            try:
                try:
                    seed(source, destination)
                except sqlite3.OperationalError as error:
                    self.fail(f"clean WAL database was not copied from read-only source: {error}")
            finally:
                source.chmod(0o755)

            copied = sqlite3.connect(destination / "clean-wal.db")
            self.assertEqual(copied.execute("select body from messages").fetchone()[0], "kept")
            copied.close()

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
                seed(source, destination)
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
                seed(source, destination)
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
                seed(source, destination)

    def test_rejects_absolute_symlink_outside_opt_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "passwd").symlink_to("/etc/passwd")

            with self.assertRaisesRegex(ValueError, "absolute symlink target must be below /opt/data"):
                seed(source, destination)

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
            (source / "state.db-wal").write_text("do not copy", encoding="utf-8")
            (source / "state.db-shm").write_text("do not copy", encoding="utf-8")

            seed(source, destination)

            self.assertEqual((destination / "config.yaml").read_text(encoding="utf-8"), "gateway: docker\n")
            self.assertFalse((destination / ".op.env").exists())
            self.assertFalse((destination / ".xurl").exists())
            self.assertFalse((destination / ".browser").exists())
            self.assertFalse((destination / "state.db-wal").exists())
            self.assertFalse((destination / "state.db-shm").exists())
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
                seed(source, destination)


if __name__ == "__main__":
    unittest.main()
