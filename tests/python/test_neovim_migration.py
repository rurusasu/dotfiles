"""Run the Neovim migration against disposable homes, without Nix or Neovim."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "nix/modules/nvim/migrate-legacy.sh"
SUFFIX = ".pre-home-manager"
TARGETS = ("init.lua", "lua", "after/lsp")


def snapshot(root: Path) -> dict:
    """Record contents, links, modes and identities without following links."""
    result = {}
    for path in sorted(root.rglob("*")):
        info = path.lstat()
        content = None
        if path.is_symlink():
            content = os.readlink(path)
        elif stat.S_ISREG(info.st_mode):
            content = path.read_bytes()
        result[str(path.relative_to(root))] = (
            info.st_mode,
            info.st_ino,
            info.st_mtime_ns,
            content,
        )
    return result


class NeovimMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.relative = ".config/nvim"
        self.config = self.home / self.relative
        self.store = self.root / "store"
        self.store.mkdir()

    def legacy(self) -> None:
        (self.config / "lua/config").mkdir(parents=True)
        (self.config / "after/lsp").mkdir(parents=True)
        (self.config / "after/ftplugin").mkdir()
        (self.config / "init.lua").write_text("-- personal init\n")
        (self.config / "init.lua").chmod(0o600)
        (self.config / "lua/config/personal.lua").write_text("return 42\n")
        (self.config / "after/lsp/nixd.lua").write_text("return { custom = true }\n")
        (self.config / "after/ftplugin/lua.lua").write_text("-- keep this\n")

    def invoke(self, mode: str, **environment: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env.pop("DRY_RUN", None)
        env.update(HOME=str(self.home), **environment)
        return subprocess.run(
            ["bash", str(MIGRATION), mode, self.relative, str(self.store)],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_success(self, result: subprocess.CompletedProcess) -> None:
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_rejected_without_changes(self) -> None:
        before = snapshot(self.root)
        for mode in ("check", "apply"):
            result = self.invoke(mode)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("Neovim migration:", result.stderr)
            self.assertEqual(snapshot(self.root), before)

    def managed_link(self, name: str) -> None:
        target = self.store / ("a" * 32 + "-home-manager-files") / self.relative / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if name == "init.lua":
            target.write_text("-- managed init\n")
        else:
            target.mkdir()
        (self.config / name).parent.mkdir(parents=True, exist_ok=True)
        (self.config / name).symlink_to(target)

    def test_preflight_is_read_only(self) -> None:
        self.legacy()
        before = snapshot(self.root)
        self.assert_success(self.invoke("check"))
        self.assertEqual(snapshot(self.root), before)

    def test_backup_preserves_contents_modes_and_unrelated_after(self) -> None:
        self.legacy()
        before = snapshot(self.config)
        self.assert_success(self.invoke("apply"))
        after = snapshot(self.config)
        for name in TARGETS:
            self.assertFalse(os.path.lexists(self.config / name))
            for key, value in before.items():
                if key == name or key.startswith(name + "/"):
                    backup_key = name + SUFFIX + key[len(name) :]
                    self.assertEqual(after[backup_key], value)
        self.assertEqual(after["after/ftplugin/lua.lua"], before["after/ftplugin/lua.lua"])
        self.assertEqual(after["after/ftplugin"], before["after/ftplugin"])

    def test_repeated_apply_preserves_previous_backups(self) -> None:
        self.legacy()
        self.assert_success(self.invoke("apply"))
        before = snapshot(self.root)
        self.assert_success(self.invoke("check"))
        self.assert_success(self.invoke("apply"))
        self.assertEqual(snapshot(self.root), before)

    def test_fresh_home_does_not_create_anything(self) -> None:
        before = snapshot(self.root)
        self.assert_success(self.invoke("check"))
        self.assert_success(self.invoke("apply"))
        self.assertEqual(snapshot(self.root), before)

    def test_dry_run_including_empty_variable_is_read_only(self) -> None:
        self.legacy()
        before = snapshot(self.root)
        for dry_run in ("", "1"):
            self.assert_success(self.invoke("apply", DRY_RUN=dry_run))
            self.assertEqual(snapshot(self.root), before)

    def test_all_backup_collisions_fail_before_any_move(self) -> None:
        self.legacy()
        for name in TARGETS:
            for kind in ("file", "directory", "symlink", "dangling"):
                with self.subTest(name=name, kind=kind):
                    backup = self.config / (name + SUFFIX)
                    if kind == "file":
                        backup.write_text("previous backup")
                    elif kind == "directory":
                        backup.mkdir()
                    else:
                        backup.symlink_to(self.store if kind == "symlink" else self.root / "absent")
                    self.assert_rejected_without_changes()
                    if kind == "directory":
                        backup.rmdir()
                    else:
                        backup.unlink()

    def test_foreign_and_dangling_links_fail_closed(self) -> None:
        for name in TARGETS:
            for dangling in (False, True):
                with self.subTest(name=name, dangling=dangling):
                    (self.config / name).parent.mkdir(parents=True, exist_ok=True)
                    (self.config / name).symlink_to(self.root / "absent" if dangling else self.store)
                    self.assert_rejected_without_changes()
                    (self.config / name).unlink()

    def test_existing_managed_init_and_lua_links_keep_backups_untouched(self) -> None:
        for name in TARGETS[:2]:
            self.managed_link(name)
            (self.config / (name + SUFFIX)).write_text("previous backup")
        before = snapshot(self.root)
        self.assert_success(self.invoke("check"))
        self.assert_success(self.invoke("apply"))
        self.assertEqual(snapshot(self.root), before)

    def test_managed_lsp_link_requires_manual_durable_backup(self) -> None:
        self.managed_link("after/lsp")
        self.assert_rejected_without_changes()

    def test_dangling_managed_links_fail_closed(self) -> None:
        for name in TARGETS:
            with self.subTest(name=name):
                self.managed_link(name)
                target = (self.config / name).resolve()
                target.unlink() if target.is_file() else target.rmdir()
                self.assert_rejected_without_changes()
                (self.config / name).unlink()

    def test_managed_link_to_a_different_file_is_not_trusted(self) -> None:
        self.managed_link("init.lua")
        wrong_target = (self.config / "init.lua").resolve().with_name("different.lua")
        wrong_target.write_text("-- another managed file\n")
        (self.config / "init.lua").unlink()
        (self.config / "init.lua").symlink_to(wrong_target)
        self.assert_rejected_without_changes()

    def test_custom_xdg_directory_with_spaces(self) -> None:
        self.relative = ".custom config/nvim"
        self.config = self.home / self.relative
        self.legacy()
        self.assert_success(self.invoke("check"))
        self.assert_success(self.invoke("apply"))
        self.assertEqual(
            (self.config / ("init.lua" + SUFFIX)).read_text(), "-- personal init\n"
        )
        self.assertFalse((self.home / ".config").exists())

    def test_unsafe_config_paths_are_rejected(self) -> None:
        self.legacy()
        for relative in ("", "/absolute/nvim", "../nvim", "config/../nvim", "./nvim"):
            with self.subTest(relative=relative):
                self.relative = relative
                self.assert_rejected_without_changes()

    def test_symlinked_parent_directories_fail_closed(self) -> None:
        for parent in (".config", ".config/nvim", ".config/nvim/after"):
            with self.subTest(parent=parent):
                path = self.home / parent
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(self.store)
                self.assert_rejected_without_changes()
                path.unlink()

    def test_wrong_entry_types_fail_closed(self) -> None:
        self.config.mkdir(parents=True)
        (self.config / "init.lua").mkdir()
        self.assert_rejected_without_changes()
        (self.config / "init.lua").rmdir()
        for name in ("lua", "after", "after/lsp"):
            with self.subTest(name=name):
                path = self.config / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("not a directory")
                self.assert_rejected_without_changes()
                path.unlink()

    def test_apply_rechecks_collisions_after_successful_preflight(self) -> None:
        self.legacy()
        self.assert_success(self.invoke("check"))
        (self.config / ("after/lsp" + SUFFIX)).mkdir()
        self.assert_rejected_without_changes()

    def test_no_clobber_race_stops_before_linking(self) -> None:
        self.legacy()
        commands = self.root / "commands"
        commands.mkdir()
        real_mv = shutil.which("mv")
        self.assertIsNotNone(real_mv)
        bash = shutil.which("bash")
        self.assertIsNotNone(bash)
        wrapper = commands / "mv"
        wrapper.write_text(
            f'#!{bash}\n'
            'destination="${!#}"\n'
            'mkdir "$destination"\n'
            'printf "keep me" > "$destination/sentinel"\n'
            f'exec "{real_mv}" "$@"\n'
        )
        wrapper.chmod(0o755)
        result = self.invoke("apply", PATH=f"{commands}:{os.environ['PATH']}")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertRegex(
            result.stderr,
            r"Neovim migration: (source remains after backup; refusing to link|could not preserve):",
        )
        self.assertTrue((self.config / "init.lua").is_file())
        self.assertTrue((self.config / "lua/config/personal.lua").is_file())
        self.assertEqual((self.config / ("init.lua" + SUFFIX) / "sentinel").read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
