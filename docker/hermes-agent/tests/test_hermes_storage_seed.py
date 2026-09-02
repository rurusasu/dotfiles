from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from hermes_storage_seed import seed


class HermesStorageSeedTests(unittest.TestCase):
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
