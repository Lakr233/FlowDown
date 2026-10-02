#!/usr/bin/env python3
"""Regression tests for scan.license.sh, run against a throwaway repository.

Run with: python3 -m unittest discover -s Resources/DevKit/tests
"""

import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts"))

RESOLVING_XCODEBUILD = """#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = "-clonedSourcePackagesDirPath" ]; then
    mkdir -p "$2/checkouts/RemotePackage"
    echo "remote package license" > "$2/checkouts/RemotePackage/LICENSE"
  fi
  shift
done
"""

FAILING_XCODEBUILD = """#!/bin/sh
exit 1
"""


def write(path, content, executable=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    if executable:
        os.chmod(path, 0o755)


class ScanLicenseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.directory.name, "repo")
        self.stubs = os.path.join(self.directory.name, "stubs")
        self.licenses = os.path.join(self.repo, "FlowDown", "BundledResources", "OpenSourceLicenses.md")
        self.untracked = os.path.join(self.repo, "Frameworks", "Storage", "Sources", "Untracked.swift")

        os.makedirs(os.path.join(self.repo, "FlowDown.xcworkspace"))
        script = os.path.join(self.repo, "Resources", "DevKit", "scripts", "scan.license.sh")
        os.makedirs(os.path.dirname(script))
        shutil.copy2(os.path.join(SCRIPTS_DIR, "scan.license.sh"), script)
        os.chmod(script, 0o755)
        write(os.path.join(self.repo, ".gitignore"), ".build\n")
        write(os.path.join(self.repo, "Frameworks", "Storage", "LICENSE"), "storage license\n")
        write(self.licenses, "original licenses\n")

        self.environment = dict(os.environ)
        for variable in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.environment.pop(variable, None)
        self.environment["ZDOTDIR"] = self.directory.name
        self.environment["PATH"] = self.stubs + os.pathsep + self.environment.get("PATH", "")
        self.environment["ALLOW_DIRTY"] = "1"

        self.git("init", "-q")
        self.git("add", "-A")
        self.git("commit", "-qm", "Initial Commit")

        # Ignored SwiftPM build output and untracked work the scan must leave alone.
        write(
            os.path.join(self.repo, "Frameworks", "Storage", ".build", "checkouts", "BuildCopy", "LICENSE"),
            "duplicated license\n",
        )
        write(self.untracked, "struct Untracked {}\n")
        write(os.path.join(self.stubs, "xcbeautify"), "#!/bin/sh\nexec cat\n", executable=True)

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *arguments):
        subprocess.run(
            [
                "git",
                "-c", "user.name=FlowDown",
                "-c", "user.email=devkit@example.invalid",
                "-c", "commit.gpgsign=false",
                "-c", "core.hooksPath=/dev/null",
                *arguments,
            ],
            cwd=self.repo,
            env=self.environment,
            check=True,
            capture_output=True,
        )

    def scan(self, xcodebuild):
        write(os.path.join(self.stubs, "xcodebuild"), xcodebuild, executable=True)
        return subprocess.run(
            ["/bin/zsh", os.path.join(self.repo, "Resources", "DevKit", "scripts", "scan.license.sh")],
            cwd=self.repo,
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def read_licenses(self):
        with open(self.licenses, encoding="utf-8") as handle:
            return handle.read()

    def test_dirty_scan_keeps_untracked_framework_files(self):
        result = self.scan(RESOLVING_XCODEBUILD)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(os.path.isfile(self.untracked))
        licenses = self.read_licenses()
        self.assertIn("## Storage", licenses)
        self.assertIn("## RemotePackage", licenses)
        self.assertNotIn("## BuildCopy", licenses)

    def test_failed_resolution_exits_without_rewriting_licenses(self):
        result = self.scan(FAILING_XCODEBUILD)

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_licenses(), "original licenses\n")
        self.assertTrue(os.path.isfile(self.untracked))


if __name__ == "__main__":
    unittest.main()
