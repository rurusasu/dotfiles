"""Runtime checks for CI cancellation and the aggregate completion gate."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CiJobRoutingTests(unittest.TestCase):
    def test_chezmoi_source_checks_rendered_wslg_font_configuration(self) -> None:
        if shutil.which("pwsh") is None:
            self.skipTest("requires PowerShell to execute the Windows workflow step")
        workflow = (ROOT / ".github/workflows/ci-chezmoi.yml").read_text()
        step = re.search(
            r"(?ms)^      - name: Verify the managed Windows targets\n"
            r"        shell: pwsh\n        run: \|\n(?P<script>.*?)"
            r"(?=^      - name:|\Z)",
            workflow,
        )
        self.assertIsNotNone(step)
        assert step is not None
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
                    "        print('.config/dotfiles/wslg-fontconfig.conf\\n.config/git/config\\n.wslgconfig\\n"
                    "AppData/Local/superfile/config.toml\\n"
                    "Documents/PowerShell/Microsoft.PowerShell_profile.ps1')\n"
                    "    else:\n"
                    "        print('.chezmoiscripts/deploy/keybindings/sync_wsl_keybindings.ps1\\n"
                    ".chezmoiscripts/deploy/terminals/deploy.ps1\\n"
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
                script_path.write_text(textwrap.dedent(step.group("script")))
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
        workflow = (ROOT / ".github/workflows/ci-nix.yml").read_text()
        aggregate = re.search(r"(?ms)^  complete:\n(.*?)(?=^  [\w-]+:\n|\Z)", workflow)[
            1
        ]
        script = aggregate.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in script.splitlines())
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
                result = subprocess.run(
                    ["bash", "-c", script],
                    env=env | changes,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(
                    result.returncode, expected, result.stdout + result.stderr
                )


if __name__ == "__main__":
    unittest.main()
