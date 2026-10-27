"""Runtime contracts for CI routing, authentication, caches, and image selection."""

from __future__ import annotations

import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci-nix.yml"
ACTION_PATH = ROOT / ".github/actions/detect-ci-changes/action.yml"
OUTPUTS = {"nix", "chezmoi", "other", "linux", "darwin", "wsl", "windows"}
UNIX = {"nix", "linux", "darwin", "wsl"}


def workflow_script(path: Path, name: str, job: str = "") -> str:
    source = path.read_text(encoding="utf-8")
    if job:
        match = re.search(rf"(?ms)^  {re.escape(job)}:\n(.*?)(?=^  [\w-]+:\n|\Z)", source)
        assert match is not None, f"Missing workflow job: {job}"
        source = match[1]
    step = re.search(
        rf"(?ms)^(?P<indent> +)- name: {re.escape(name)}\n(?P<body>.*?)"
        r"(?=^(?P=indent)- name:|^  [\w-]+:\n|\Z)", source,
    )
    assert step is not None, f"Missing workflow step: {name}"
    return textwrap.dedent(step["body"].split("run: |\n", 1)[1])


def run_bash(script: str, environment: dict[str, str], cwd: Path | None = None, check: bool = False):
    return subprocess.run(
        ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
        env=environment, cwd=cwd, check=check, capture_output=True, text=True,
    )


class CiWorkflowRoutingContractTests(unittest.TestCase):
    """Run build steps with external commands replaced at the process boundary."""

    def test_cache_pruning_deletes_only_older_confirmed_main_generations(self) -> None:
        with mock.patch.object(sys, "path", [str(ROOT / "scripts/python"), *sys.path]):
            from prepare_ci_nix_cache import prune_cache

        prefix = "ci-nix-v2-test-"
        key = prefix + "current"
        old = {"id": 1, "key": prefix + "old", "ref": "refs/heads/main", "created_at": "2026-01"}
        protected = [
            old | {"id": 2, "key": "unrelated-old"},
            old | {"id": 3, "ref": "refs/pull/1/merge"},
            old | {"id": 4, "created_at": "2026-03"},
        ]
        environment = {
            "GITHUB_REF": "refs/heads/main", "GITHUB_API_URL": "https://api.github.com",
            "GITHUB_REPOSITORY": "owner/repo", "GITHUB_TOKEN": "fixture-token",
        }
        for confirmed in (False, True):
            pages = [{"actions_caches": [old, *protected]}, {"actions_caches": []}]
            if confirmed:
                pages[1]["actions_caches"].append(old | {"id": 5, "key": key, "created_at": "2026-02"})
            with (
                self.subTest(confirmed=confirmed),
                mock.patch.dict(os.environ, environment),
                mock.patch("prepare_ci_nix_cache.subprocess.run", return_value=subprocess.CompletedProcess([], 0, json.dumps(pages))) as run,
            ):
                prune_cache(key, prefix)
                self.assertIn("--paginate", run.call_args_list[0].args[0])
                self.assertIn("--slurp", run.call_args_list[0].args[0])
                deleted = [call.args[0][-1] for call in run.call_args_list if "DELETE" in call.args[0]]
                self.assertEqual(deleted, ["https://api.github.com/repos/owner/repo/actions/caches/1"] if confirmed else [])
                self.assertNotIn("fixture-token", str([call.args for call in run.call_args_list]))
        with (
            mock.patch.dict(os.environ, environment),
            mock.patch("prepare_ci_nix_cache.subprocess.run", side_effect=subprocess.CalledProcessError(1, ["gh", "api"])) as run,
        ):
            prune_cache(key, prefix)
            self.assertEqual(run.call_count, 1)

    def test_linux_build_installs_declared_hardware_without_identity_inference(
        self,
    ) -> None:
        script = workflow_script(WORKFLOW, "Build Linux configurations and checks", "linux-build")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            nix = directory / "nix"
            nix.write_text(
                "#!/bin/bash\n"
                "[[ ! -v DOTFILES_USER && ! -v DOTFILES_HOME ]] || exit 64\n"
                'printf "%s\\0" "$@" > "$INVOCATION_LOG"\n'
                f"printf '/nix/store/{'b' * 32}-system\\n'\n"
            )
            nix.chmod(0o755)
            installer = directory / "install"
            installer.write_text(
                '#!/bin/bash\nprintf "%s\\0" "$@" > "$INSTALL_LOG"\n'
            )
            installer.chmod(0o755)
            environment = dict(os.environ)
            environment.update(
                PATH=f"{directory}:{environment['PATH']}",
                GITHUB_WORKSPACE=temporary,
                INVOCATION_LOG=str(directory / "invocation"),
                INSTALL_LOG=str(directory / "install-arguments"),
            )
            for variable in (
                "DOTFILES_USER",
                "DOTFILES_HOME",
            ):
                environment.pop(variable, None)
            run_bash(script, environment, check=True)
            invocation = (directory / "invocation").read_text().split("\0")[:-1]
            self.assertEqual(
                (directory / "install-arguments").read_text().split("\0")[:-1],
                [
                    "-D",
                    "-m",
                    "0644",
                    f"{temporary}/nix/tests/fixtures/hardware-configuration.nix",
                    "/etc/nixos/hardware-configuration.nix",
                ],
            )
        self.assertEqual(invocation[:2], ["build", "--impure"])
        self.assertIn(
            ".#nixosConfigurations.linux.config.system.build.toplevel",
            invocation,
        )
        self.assertIn(
            ".#homeConfigurations.x86_64-linux.activationPackage", invocation
        )

    def test_wsl_prebuild_exports_zstd_cache_and_fails_closed(self) -> None:
        script = workflow_script(WORKFLOW, "Build the WSL system closure and export a local cache", "wsl-prebuild")
        expected_paths = [
            f"/nix/store/{'b' * 32}-hermes",
        ]
        for copy_exit, nar_url, references, expected_exit, diagnostic in (
            (0, "nar/private.nar.zst", "", 0, ""),
            (47, "nar/private.nar.zst", "", 47, ""),
            (0, "../outside.nar", "", 1, "Invalid NAR location"),
            (0, "nar/missing.nar", "", 1, "Missing NAR payload"),
            (0, "nar/private.nar.zst", "outside-closure", 1, "Incomplete reference closure"),
        ):
            with (
                self.subTest(copy_exit=copy_exit, nar_url=nar_url, references=references),
                tempfile.TemporaryDirectory() as temporary,
            ):
                directory = Path(temporary)
                runner_temp = directory / "container runner temp"
                runner_temp.mkdir()
                output = directory / "step-output"
                output.touch()
                nix = directory / "nix"
                nix.write_text(
                    f"#!{sys.executable}\n"
                    "import os, pathlib, sys\n"
                    "from urllib.parse import urlsplit, parse_qs\n"
                    f"paths = {expected_paths!r}\n"
                    "if sys.argv[1:] == ['--version']:\n"
                    "    print('nix boundary double')\n"
                    "elif sys.argv[1] == 'build':\n"
                    "    assert '.#nixosConfigurations.nixos.config.system.build.toplevel' in sys.argv\n"
                    "    print(paths[0])\n"
                    "elif sys.argv[1:3] == ['copy', '--to']:\n"
                    "    assert sys.argv[4:] == paths\n"
                    "    target = urlsplit(sys.argv[3])\n"
                    "    assert target.scheme == 'file' and not target.netloc\n"
                    "    assert parse_qs(target.query) == {'compression': ['zstd']}\n"
                    "    if os.environ['COPY_EXIT'] != '0': raise SystemExit(int(os.environ['COPY_EXIT']))\n"
                    "    cache = pathlib.Path(target.path)\n"
                    "    (cache / 'nar').mkdir(exist_ok=True)\n"
                    "    (cache / 'nar/private.nar.zst').write_text('cache')\n"
                    "    (cache / (paths[0].split('/')[-1].split('-')[0] + '.narinfo')).write_text(\n"
                    "        f'StorePath: {paths[0]}\\nURL: {os.environ[\"NAR_URL\"]}\\nReferences: {os.environ[\"NAR_REFS\"]}\\n')\n"
                    "elif sys.argv[1:3] == ['path-info', '--recursive']:\n"
                    "    print(paths[0])\n"
                    "else:\n"
                    "    raise SystemExit(64)\n"
                )
                nix.chmod(0o755)
                nix_store = directory / "nix-store"
                nix_store.write_text(
                    f"#!{sys.executable}\n"
                    "import sys\n"
                    "assert sys.argv[1:5] == ['--store', 'https://cache.nixos.org', '--check-validity', '--print-invalid']\n"
                    "print('\\n'.join(sys.argv[5:]))\n"
                )
                nix_store.chmod(0o755)
                environment = dict(os.environ)
                environment.update(
                    PATH=f"{directory}:{environment['PATH']}",
                    RUNNER_TEMP=str(runner_temp),
                    GITHUB_OUTPUT=str(output),
                    COPY_EXIT=str(copy_exit),
                    NAR_URL=nar_url,
                    NAR_REFS=references,
                    DOTFILES_CI_BINARY_CACHE=str(runner_temp / "persistent-cache"),
                )
                (runner_temp / "persistent-cache").mkdir()
                result = run_bash(script, environment)
                self.assertEqual(
                    result.returncode, expected_exit, result.stdout + result.stderr
                )
                if expected_exit:
                    if diagnostic:
                        self.assertIn(diagnostic, result.stderr)
                    self.assertEqual(
                        output.read_text(),
                        "",
                        "failed exports must not publish an artifact path",
                    )
                    self.assertFalse(
                        (
                            runner_temp / "wsl-nix-cache-artifact/wsl-nix-cache.tar"
                        ).exists()
                    )
                    if not copy_exit:
                        self.assertTrue((runner_temp / "persistent-cache/nar/private.nar.zst").is_file())
                    continue
                self.assertTrue(
                    output.is_file(),
                    "prebuild must export its actual container artifact directory",
                )
                outputs = dict(
                    line.split("=", 1) for line in output.read_text().splitlines()
                )
                artifact = Path(outputs["artifact-dir"])
                self.assertTrue(artifact.is_relative_to(runner_temp))
                self.assertEqual(
                    sorted(path.name for path in artifact.iterdir()),
                    ["wsl-nix-cache.tar", "wsl-system-paths.txt"],
                )
                self.assertEqual(
                    (artifact / "wsl-system-paths.txt").read_text().splitlines(),
                    expected_paths,
                )
                with tarfile.open(artifact / "wsl-nix-cache.tar") as archive:
                    self.assertIn("./nar/private.nar.zst", archive.getnames())
                    self.assertIn("./public-paths.txt", archive.getnames())
                self.assertTrue(
                    (runner_temp / "persistent-cache/nar/private.nar.zst").is_file(),
                    "transport pruning must preserve the persistent cache",
                )




class BootstrapCiImageTests(unittest.TestCase):
    def test_authentication_uses_nix_config_home_and_keeps_tokens_private(self) -> None:
        for use_xdg, wsl, owned_home in itertools.product((True, False), repeat=3):
            with (
                self.subTest(use_xdg=use_xdg, wsl=wsl, owned_home=owned_home),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = Path(directory)
                home = root / "passwd-home"
                home.mkdir()
                config = root / "xdg" if use_xdg and owned_home else home / ".config"
                tools = root / "bin"
                tools.mkdir()
                commands = {
                    "getent": '#!/bin/bash\nprintf "fixture:x:0:0:Fixture:%s:/bin/bash\\n" "$FALLBACK_HOME"\n',
                    "nix": (
                        '#!/bin/bash\ncase "$*" in\n'
                        '  "config show access-tokens") field=access-tokens ;;\n'
                        '  "config show substituters") field=extra-substituters ;;\n'
                        '  "config show trusted-public-keys") field=extra-trusted-public-keys ;;\n'
                        '  *) exit 64 ;;\nesac\n'
                        'grep "^$field = " "$EXPECTED_CONFIG/nix/bootstrap-ci.conf" | cut -d= -f2-\n'
                    ),
                }
                for name, content in commands.items():
                    command = tools / name
                    command.write_text(content)
                    command.chmod(0o755)
                environment = {
                    key: value
                    for key, value in os.environ.items()
                    if key
                    not in ("XDG_CONFIG_HOME", "NIX_CONFIG", "NIX_USER_CONF_FILES")
                }
                environment.update(
                    HOME=str(home if owned_home else root / "missing-home"),
                    FALLBACK_HOME=str(home),
                    EXPECTED_CONFIG=str(config),
                    GITHUB_TOKEN="fixture-token-not-a-real-secret",
                    GITHUB_WORKSPACE=str(root / "checkout"),
                    GITHUB_ENV=str(root / "github-env"),
                    GIT_CONFIG_SYSTEM=str(root / "gitconfig"),
                    PATH=f"{tools}{os.pathsep}{os.environ['PATH']}",
                )
                if use_xdg:
                    environment["XDG_CONFIG_HOME"] = str(config)
                if wsl:
                    environment.pop("GITHUB_WORKSPACE")
                script = ROOT / "scripts/sh/configure-bootstrap-ci-nix.sh"
                for _ in range(2):
                    result = subprocess.run(
                        ["bash", str(script), *(["--wsl"] if wsl else [])],
                        env=environment,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn(
                        environment["GITHUB_TOKEN"], result.stdout + result.stderr
                    )
                environment_file = Path(environment["GITHUB_ENV"])
                if owned_home:
                    self.assertFalse(environment_file.exists())
                else:
                    self.assertEqual(
                        environment_file.read_text(),
                        f"HOME={home}\nXDG_CONFIG_HOME=\n" * 2,
                    )
                secret_file = config / "nix/bootstrap-ci.conf"
                self.assertEqual(secret_file.stat().st_mode & 0o777, 0o600)
                self.assertEqual(
                    (config / "nix/nix.conf")
                    .read_text()
                    .count(f"include {secret_file}"),
                    1,
                )
                if wsl:
                    self.assertFalse(Path(environment["GIT_CONFIG_SYSTEM"]).exists())
                    self.assertIn("max-jobs = 2", secret_file.read_text())
                    continue
                trusted_directories = subprocess.run(
                    ["git", "config", "--system", "--get-all", "safe.directory"],
                    env=environment,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(trusted_directories.returncode, 0)
                self.assertNotIn(
                    environment["GITHUB_TOKEN"],
                    Path(environment["GIT_CONFIG_SYSTEM"]).read_text(),
                )
                self.assertEqual(
                    trusted_directories.stdout.splitlines(),
                    [environment["GITHUB_WORKSPACE"]],
                )

    def run_step(
        self, name: str, *, docker_exit: int = 0, **environment: str
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        script = workflow_script(WORKFLOW, name)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docker = root / "docker"
            docker.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                '[[ "$1 $2 $3" == "buildx imagetools inspect" ]]\n'
                'printf "%s\\n" "$DOCKER_RESULT"\n'
                'exit "$DOCKER_EXIT"\n'
            )
            docker.chmod(0o755)
            output = root / "output"
            result = run_bash(
                script,
                {
                    **os.environ,
                    "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
                    "GITHUB_OUTPUT": str(output),
                    "GITHUB_REPOSITORY": "RuruSasu/Dotfiles",
                    "DEFINITION_HASH": "a" * 64,
                    "CAN_PUBLISH": "true",
                    "DOCKER_EXIT": str(docker_exit),
                    "DOCKER_RESULT": "sha256:" + "b" * 64,
                    **environment,
                },
            )
            return result, output.read_text() if output.exists() else ""

    def test_existing_image_is_reused_without_a_build(self) -> None:
        result, output = self.run_step("Select image for the tool definition")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            output,
            f"tag=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:{'a' * 64}\nbuild=false\n",
        )

    def test_missing_image_is_built_only_with_publish_authority(self) -> None:
        for can_publish, expected_exit in (("true", 0), ("false", 1)):
            with self.subTest(can_publish=can_publish):
                result, output = self.run_step(
                    "Select image for the tool definition",
                    docker_exit=1,
                    CAN_PUBLISH=can_publish,
                )
                self.assertEqual(result.returncode, expected_exit, result.stderr)
                self.assertEqual("build=true\n" in output, can_publish == "true")

    def test_missing_definition_hash_fails_before_selecting_an_image(self) -> None:
        result, output = self.run_step(
            "Select image for the tool definition", DEFINITION_HASH=""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")

    def test_consumers_receive_only_a_valid_immutable_reference(self) -> None:
        for digest, expected_exit in (("sha256:" + "b" * 64, 0), ("invalid", 1)):
            with self.subTest(digest=digest):
                result, output = self.run_step(
                    "Resolve immutable image reference",
                    IMAGE="ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools:tag",
                    DOCKER_RESULT=digest,
                )
                self.assertEqual(result.returncode, expected_exit, result.stderr)
                expected_output = (
                    f"image=ghcr.io/rurusasu/dotfiles/bootstrap-ci-tools@{digest}\n"
                    if expected_exit == 0
                    else ""
                )
                self.assertEqual(output, expected_output)


class CiJobRoutingTests(unittest.TestCase):
    def test_chezmoi_source_checks_rendered_wslg_font_configuration(self) -> None:
        if shutil.which("pwsh") is None:
            self.skipTest("requires PowerShell to execute the Windows workflow step")
        script = workflow_script(ROOT / ".github/workflows/ci-chezmoi.yml", "Verify the managed Windows targets")
        canonical = '<?xml version="1.0"?>\n<fontconfig><dir>/fixture/fonts</dir></fontconfig>\n'
        for case, expected in (
            ("windows-home", 0),
            ("bad-path", 1),
            ("malformed-xml", 1),
            ("different-xml", 1),
            ("render-error", 1),
        ):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                workspace = Path(temporary)
                (workspace / "chezmoi").mkdir()
                xml_path = workspace / "nix/modules/fonts/wsl-fontconfig.conf"
                xml_path.parent.mkdir(parents=True)
                xml_path.write_text(canonical)
                executable = workspace / "chezmoi-cli"
                executable.mkdir()
                chezmoi = executable / "chezmoi"
                chezmoi.write_text(
                    f"#!{sys.executable}\n"
                    "import json, os, sys\n"
                    "args = sys.argv[1:]\n"
                    "case = os.environ['RENDER_CASE']\n"
                    "data = json.loads(args[args.index('--override-data') + 1])['chezmoi']\n"
                    "if case == 'windows-home' and data != "
                    "{'os': 'windows', 'homeDir': 'C:/Users/ci'}: raise SystemExit(64)\n"
                    "if 'managed' in args:\n"
                    "    kind = args[args.index('--include') + 1]\n"
                    "    if kind == 'files':\n"
                    "        print('.config/dotfiles/wslg-fontconfig.conf\\n.config/git/config\\n.config/wezterm/wezterm.lua\\n.wslgconfig\\n"
                    "AppData/Local/superfile/config.toml\\n"
                    "Documents/PowerShell/Microsoft.PowerShell_profile.ps1')\n"
                    "    else:\n"
                    "        print('.chezmoiscripts/deploy/keybindings/sync_wsl_keybindings.ps1\\n"
                    ".chezmoiscripts/deploy/terminals/install_udev_gothic_nf.ps1')\n"
                    "elif 'execute-template' in args:\n"
                    "    if case == 'render-error': raise SystemExit(41)\n"
                    "    path = args[args.index('--file') + 1]\n"
                    "    if path.endswith('dot_wslgconfig.tmpl'):\n"
                    "        mount = '/mnt//oot' if case == 'bad-path' else '/mnt/c/Users/ci'\n"
                    "        print('[system-distro-env]\\nFONTCONFIG_FILE=' + mount + "
                    "'/.config/dotfiles/wslg-fontconfig.conf')\n"
                    "    else:\n"
                    "        rendered = os.environ['CANONICAL_XML']\n"
                    "        if case == 'malformed-xml': rendered = '<fontconfig>'\n"
                    "        if case == 'different-xml': rendered = '<fontconfig><dir>/other</dir></fontconfig>'\n"
                    "        print(rendered, end='')\n"
                    "else: raise SystemExit(65)\n"
                )
                chezmoi.chmod(0o755)
                script_path = workspace / "verify.ps1"
                script_path.write_text(script)
                result = subprocess.run(
                    [
                        "pwsh",
                        "-NoLogo",
                        "-NoProfile",
                        "-NonInteractive",
                        "-File",
                        str(script_path),
                    ],
                    env=os.environ
                    | {
                        "PATH": f"{executable}{os.pathsep}{os.environ['PATH']}",
                        "GITHUB_WORKSPACE": str(workspace),
                        "RENDER_CASE": case,
                        "CANONICAL_XML": canonical,
                    },
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(
                    result.returncode, expected, result.stdout + result.stderr
                )

    def test_bootstrap_aggregate_accepts_no_work_but_rejects_missing_required_jobs(
        self,
    ) -> None:
        script = workflow_script(WORKFLOW, "Verify routed job results", "complete")
        variables = set(re.findall(r"\$\{([A-Z_]+)\}", script))
        env = (
            os.environ
            | {
                key: "skipped" if key.endswith("_RESULT") else "false"
                for key in variables
            }
            | {"CHANGES_RESULT": "success"}
        )
        for changes, expected in (
            ({}, 0),
            ({"CHANGES_RESULT": "failure"}, 1),
            ({"LINUX_BUILD_REQUIRED": "true"}, 1),
            ({"NIX_REQUIRED": "true"}, 1),
            ({"BASH_REQUIRED": "true"}, 1),
            ({"BASH_REQUIRED": "true", "BASH_RESULT": "failure"}, 1),
            ({"BASH_REQUIRED": "true", "BASH_RESULT": "success"}, 0),
            ({"BASH_RESULT": "success"}, 1),
            (
                {
                    "TOOLS_REQUIRED": "true",
                    "TOOLS_RESULT": "success",
                    "NIX_REQUIRED": "true",
                    "NIX_RESULT": "success",
                    "LINUX_BUILD_REQUIRED": "true",
                    "LINUX_BUILD_RESULT": "success",
                },
                0,
            ),
            ({"WINDOWS_REQUIRED": "true"}, 1),
            ({"WINDOWS_REQUIRED": "true", "WINDOWS_INSTALLER_RESULT": "success"}, 0),
            ({"WINDOWS_INSTALLER_RESULT": "success"}, 1),
            ({"DARWIN_RESULT": "success"}, 1),
        ):
            with self.subTest(changes=changes):
                result = run_bash(script, env | changes)
                self.assertEqual(
                    result.returncode, expected, result.stdout + result.stderr
                )


class DetectCiActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.script = workflow_script(ACTION_PATH, "Classify changed paths")

    def test_non_all_mode_classifies_git_paths_and_rejects_invalid_revisions(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._git(repository, "rev-parse", "HEAD")
            head_sha = self._commit_nix_config(repository)

            for base in (base_sha, "0" * 40):
                with self.subTest(base=base):
                    completed, output_path, runner_temp = self._run_action_script(
                        repository,
                        base_sha=base,
                        head_sha=head_sha,
                        run_all=False,
                    )

                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    self.assertEqual(
                        self._read_outputs(output_path),
                        {name: name in UNIX for name in OUTPUTS},
                    )
                    self.assertEqual(
                        (runner_temp / "ci-changed-paths").read_text(encoding="utf-8"),
                        "README.md\0nix/example.nix\0"
                        if base == "0" * 40
                        else "nix/example.nix\0",
                    )

            for base, head in (("missing-base", head_sha), (base_sha, "missing-head")):
                with self.subTest(base=base, head=head):
                    completed, output_path, _ = self._run_action_script(
                        repository, base_sha=base, head_sha=head, run_all=False
                    )
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertEqual(self._read_outputs(output_path), {})

        cases = (
            (("chezmoi/config.tmpl",), {"chezmoi", "windows"}),
            (("nix/modules/aerospace/default.nix",), {"nix", "darwin"}),
            (("nix/modules/1password/op-ssh-sign-wsl",), {"nix", "wsl"}),
            (("nix/modules/editors/vscode.nix",), {"nix", "wsl"}),
            (("nix/modules/1password/default.nix",), UNIX),
            (
                ("nix/modules/fonts/wsl-fontconfig.conf",),
                {"nix", "wsl", "chezmoi", "windows"},
            ),
            (
                ("nix/defaults.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/home/keybindings/bindings.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/home/keybindings/generated.json",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty-renderer.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty-wsl.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/editors/nvim/neovim.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (("nix/modules/hyprland/hyprland-renderer.nix",), {"nix", "linux"}),
            (("windows/winget/packages.json",), {"nix", "chezmoi", "windows"}),
            (("scripts/sh/install-macos.sh",), OUTPUTS),
            ((".github/workflows/ci-chezmoi.yml",), OUTPUTS),
            (("taskfiles/hermes/taskfile.yml",), OUTPUTS),
            (("README.md", "docs/architecture.md", "nix/hosts/AGENTS.md"), set()),
            (("chezmoi/prompt.md",), {"chezmoi", "windows"}),
            (("chezmoi/dot_codex/AGENTS.md",), {"chezmoi", "windows"}),
            (("nix/modules/shells/bash/bashrc",), UNIX),
            (("config/other.json",), {"other"}),
            (
                ("nix/odd\n name.nix", "chezmoi/config.tmpl"),
                UNIX | {"chezmoi", "windows"},
            ),
        )
        for paths, categories in cases:
            with self.subTest(paths=paths), tempfile.TemporaryDirectory() as temporary:
                repository = self._make_test_repository(Path(temporary))
                base_sha = self._git(repository, "rev-parse", "HEAD")
                for path in paths:
                    target = repository / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("changed\n", encoding="utf-8")
                self._git(repository, "add", ".")
                self._git(repository, "commit", "-m", "change classified paths")
                head_sha = self._git(repository, "rev-parse", "HEAD")
                completed, output_path, _ = self._run_action_script(
                    repository, base_sha=base_sha, head_sha=head_sha, run_all=False
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(
                    self._read_outputs(output_path),
                    {name: name in categories for name in OUTPUTS},
                )

    def test_run_all_mode_invokes_the_detector_all_flag(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha="unused-base",
                head_sha="unused-head",
                run_all=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                self._read_outputs(output_path), dict.fromkeys(OUTPUTS, True)
            )
            self.assertFalse((runner_temp / "ci-changed-paths").exists())

    def test_deleted_renamed_and_type_changed_paths_keep_their_category(self) -> None:
        for change in ("delete", "rename", "type"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                repository = self._make_test_repository(Path(temporary))
                base_sha = self._commit_nix_config(repository)
                path = repository / "nix/example.nix"
                if change == "rename":
                    self._git(repository, "mv", "nix/example.nix", "renamed-installer.sh")
                else:
                    path.unlink()
                    if change == "type":
                        path.symlink_to("../target")
                self._git(repository, "add", "-A")
                self._git(repository, "commit", "-m", change)
                completed, output_path, runner_temp = self._run_action_script(
                    repository,
                    base_sha=base_sha,
                    head_sha=self._git(repository, "rev-parse", "HEAD"),
                    run_all=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertTrue(self._read_outputs(output_path)["nix"])
                paths = {"nix/example.nix"}
                if change == "rename":
                    paths.add("renamed-installer.sh")
                self.assertEqual(
                    sorted((runner_temp / "ci-changed-paths").read_text().split("\0")[:-1]), sorted(paths)
                )

    def test_pull_request_ignores_changes_only_on_the_base_branch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            self._git(repository, "branch", "pull-request")
            (repository / "chezmoi").mkdir()
            (repository / "chezmoi/base.tmpl").write_text("base change\n")
            self._git(repository, "add", ".")
            self._git(repository, "commit", "-m", "advance base with macOS change")
            base_sha = self._git(repository, "rev-parse", "HEAD")
            self._git(repository, "switch", "pull-request")
            head_sha = self._commit_nix_config(repository)

            completed, output_path, _ = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
                event_name="pull_request",
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(self._read_outputs(output_path)["nix"])
            self.assertFalse(self._read_outputs(output_path)["chezmoi"])

    def _make_test_repository(self, temporary_directory: Path) -> Path:
        repository = temporary_directory / "repository"
        repository.mkdir()
        (repository / "README.md").write_text("fixture\n", encoding="utf-8")
        self._git(repository, "init", "-q")
        self._git(repository, "config", "user.email", "ci@example.test")
        self._git(repository, "config", "user.name", "CI Test")
        self._git(repository, "add", ".")
        self._git(repository, "commit", "-m", "initial")
        return repository

    def _commit_nix_config(self, repository: Path) -> str:
        (repository / "nix").mkdir(parents=True)
        (repository / "nix" / "example.nix").write_text(
            "#!/bin/sh\n",
            encoding="utf-8",
        )
        self._git(repository, "add", ".")
        self._git(repository, "commit", "-m", "add linux installer")
        return self._git(repository, "rev-parse", "HEAD")

    def _run_action_script(
        self,
        repository: Path,
        *,
        base_sha: str,
        head_sha: str,
        run_all: bool,
        event_name: str = "push",
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
        temporary_directory = repository.parent
        runner_temp = temporary_directory / "runner-temp"
        runner_temp.mkdir(exist_ok=True)
        output_path = temporary_directory / "github-output.txt"
        output_path.write_text("", encoding="utf-8")

        environment = os.environ.copy()
        environment.update(
            {
                "GITHUB_EVENT_NAME": event_name,
                "BASE_SHA": base_sha,
                "HEAD_SHA": head_sha,
                "RUN_ALL": "true" if run_all else "false",
                "RUNNER_TEMP": str(runner_temp),
                "GITHUB_OUTPUT": str(output_path),
            }
        )
        completed = run_bash(self.script, environment, cwd=repository)
        return completed, output_path, runner_temp

    @staticmethod
    def _read_outputs(output_path: Path) -> dict[str, bool]:
        return {
            name: value == "true"
            for name, value in (
                line.split("=", maxsplit=1)
                for line in output_path.read_text(encoding="utf-8").splitlines()
            )
        }

    @staticmethod
    def _git(
        repository: Path,
        *arguments: str,
    ) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            check=True,
            cwd=repository,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip()



if __name__ == "__main__":
    unittest.main()
