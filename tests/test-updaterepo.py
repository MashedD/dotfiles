#!/usr/bin/env python3
"""Check updaterepo's safe Git command sequence with a mocked Git client."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dotfiles/.local/bin/updaterepo"


class UpdateRepoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        (self.repo / "nested").mkdir(parents=True)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "git-commands"
        git = self.bin / "git"
        git.write_text(f'''#!{os.sys.executable}
import json, os, sys
args = sys.argv[1:]
with open(os.environ["GIT_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args == ["rev-parse", "--show-toplevel"]:
    if os.environ.get("NOT_A_REPO"):
        sys.exit(128)
    print(os.environ["GIT_ROOT"])
elif args == ["status", "--porcelain", "--untracked-files=all"]:
    print(os.environ.get("GIT_STATUS", ""))
''')
        git.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        GIT_ROOT=str(self.repo), GIT_LOG=str(self.log))

    def run_helper(self):
        return subprocess.run([str(SCRIPT)], cwd=self.repo / "nested", env=self.env,
                              text=True, capture_output=True, timeout=10)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_fetch_pull_submodules_and_gitfat_from_nested_directory(self):
        (self.repo / ".gitmodules").touch()
        (self.repo / ".gitfat").touch()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands(), [
            ["rev-parse", "--show-toplevel"],
            ["fetch", "--prune"],
            ["status", "--porcelain", "--untracked-files=all"],
            ["pull", "--ff-only"],
            ["submodule", "sync", "--recursive"],
            ["submodule", "update", "--init", "--recursive"],
            ["fat", "submodule", "update", "--init", "--recursive"],
            ["fat", "pull"],
        ])

    def test_local_changes_skip_pull_and_submodule_updates(self):
        (self.repo / ".gitmodules").touch()
        self.env["GIT_STATUS"] = " M tracked.txt\n?? untracked.txt"
        result = self.run_helper()
        self.assertEqual(result.returncode, 1)
        self.assertIn("skipped pull", result.stderr)
        commands = self.commands()
        self.assertIn(["fetch", "--prune"], commands)
        self.assertNotIn(["pull", "--ff-only"], commands)
        self.assertFalse(any(command[:1] == ["submodule"] for command in commands))

    def test_outside_git_repository_fails_without_fetch(self):
        self.env["NOT_A_REPO"] = "1"
        result = self.run_helper()
        self.assertEqual(result.returncode, 1)
        self.assertIn("not inside a Git repository", result.stderr)
        self.assertEqual(self.commands(), [["rev-parse", "--show-toplevel"]])


if __name__ == "__main__":
    unittest.main()
