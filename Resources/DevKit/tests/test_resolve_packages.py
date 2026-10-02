#!/usr/bin/env python3
"""Regression tests for resolve-packages.sh restoring required pins.

Runs the script inside a throwaway repository with xcodebuild, swift and the
mlx-swift strip stubbed out, and a temporary HOME holding the DerivedData that
the resolve writes. A stale SourcePackages state is offered through
DERIVED_DATA, which required_package_pins.py ranks ahead of ~/Library.

Run with: python3 -m unittest discover -s Resources/DevKit/tests
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts"))
sys.path.insert(0, SCRIPTS_DIR)

from required_package_pins import dump_resolved  # noqa: E402

IDENTITY = "swift-argument-parser"
LOCATION = "https://github.com/apple/swift-argument-parser.git"
STALE_STATE = {"revision": "a" * 40, "version": "1.7.0"}
FRESH_STATE = {"revision": "b" * 40, "version": "1.8.2"}
RESOLVED_PATH = os.path.join("FlowDown.xcworkspace", "xcshareddata", "swiftpm", "Package.resolved")


def write(path, content, executable=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    if executable:
        os.chmod(path, 0o755)


def workspace_state(state):
    return json.dumps(
        {
            "object": {
                "dependencies": [
                    {
                        "packageRef": {"identity": IDENTITY},
                        "state": {"checkoutState": state},
                    }
                ]
            }
        }
    )


class ResolvePackagesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = self.directory.name
        self.repo = os.path.join(root, "repo")
        self.stubs = os.path.join(root, "stubs")
        home = os.path.join(root, "home")
        stale_derived_data = os.path.join(root, "stale-derived-data")
        scripts = os.path.join(self.repo, "Resources", "DevKit", "scripts")

        os.makedirs(scripts)
        for name in ("resolve-packages.sh", "required_package_pins.py"):
            shutil.copy2(os.path.join(SCRIPTS_DIR, name), os.path.join(scripts, name))
            os.chmod(os.path.join(scripts, name), 0o755)
        write(os.path.join(scripts, "strip_mlx_cuda_plugin.sh"), "#!/bin/sh\nexit 0\n", executable=True)
        write(
            os.path.join(self.repo, "Resources", "DevKit", "required-package-pins.json"),
            json.dumps(
                {
                    "files": {
                        RESOLVED_PATH: [
                            {
                                "identity": IDENTITY,
                                "kind": "remoteSourceControl",
                                "location": LOCATION,
                                "reason": "regression test",
                            }
                        ]
                    }
                }
            ),
        )
        write(os.path.join(self.repo, "Frameworks", "Storage", "Package.resolved"), "{}\n")

        write(
            os.path.join(stale_derived_data, "SourcePackages", "workspace-state.json"),
            workspace_state(STALE_STATE),
        )
        write(
            os.path.join(
                home, "Library", "Developer", "Xcode", "DerivedData", "FlowDown-test",
                "SourcePackages", "workspace-state.json",
            ),
            workspace_state(FRESH_STATE),
        )

        write(os.path.join(self.stubs, "xcodebuild"), "#!/bin/sh\nexit 0\n", executable=True)
        write(os.path.join(self.stubs, "swift"), "#!/bin/sh\nexit 0\n", executable=True)
        write(os.path.join(self.stubs, "xcbeautify"), "#!/bin/sh\nexec cat\n", executable=True)
        os.symlink(sys.executable, os.path.join(self.stubs, "python3"))

        self.environment = dict(os.environ)
        for variable in ("CI_DERIVED_DATA_PATH", "WORKSPACE", "SCHEME"):
            self.environment.pop(variable, None)
        self.environment["HOME"] = home
        self.environment["ZDOTDIR"] = root
        self.environment["DERIVED_DATA"] = stale_derived_data
        self.environment["PATH"] = self.stubs + os.pathsep + self.environment.get("PATH", "")

    def tearDown(self):
        self.directory.cleanup()

    def write_resolved(self, pins):
        content = dump_resolved({"originHash": "test", "pins": pins, "version": 3})
        write(os.path.join(self.repo, RESOLVED_PATH), content)
        return content

    def read_resolved(self):
        with open(os.path.join(self.repo, RESOLVED_PATH), encoding="utf-8") as handle:
            return handle.read()

    def resolve(self):
        return subprocess.run(
            ["/bin/zsh", os.path.join(self.repo, "Resources", "DevKit", "scripts", "resolve-packages.sh")],
            cwd=self.repo,
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def test_current_pin_ignores_stale_source_packages(self):
        before = self.write_resolved(
            [{"identity": IDENTITY, "kind": "remoteSourceControl", "location": LOCATION, "state": FRESH_STATE}]
        )

        result = self.resolve()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_resolved(), before)

    def test_pruned_pin_restores_from_fresh_resolve(self):
        self.write_resolved([])

        result = self.resolve()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        pins = json.loads(self.read_resolved())["pins"]
        self.assertEqual([pin["identity"] for pin in pins], [IDENTITY])
        self.assertEqual(pins[0]["state"], FRESH_STATE)


if __name__ == "__main__":
    unittest.main()
