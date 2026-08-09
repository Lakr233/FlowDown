#!/usr/bin/env python3
"""Keep resolver-pruned pins in Package.resolved.

See Resources/DevKit/required-package-pins.json for why this exists.

    required_package_pins.py check        # fail if a required pin is missing
    required_package_pins.py fix          # re-add it, refreshing from SourcePackages
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DEFAULT_CONFIG = os.path.join(REPO_ROOT, "Resources", "DevKit", "required-package-pins.json")


def log(message: str) -> None:
    print(f"[required-pins] {message}")


def load_resolved(path: str) -> tuple[dict, str]:
    with open(path) as handle:
        raw = handle.read()
    return json.loads(raw), raw


def dump_resolved(document: dict) -> str:
    """Serialize the way SwiftPM does, so untouched files stay byte-identical."""
    return json.dumps(document, indent=2, sort_keys=True, separators=(",", " : ")) + "\n"


def candidate_source_packages(explicit: list[str]) -> list[str]:
    candidates = list(explicit)
    for variable in ("CI_DERIVED_DATA_PATH", "DERIVED_DATA"):
        derived = os.environ.get(variable)
        if derived:
            candidates.append(os.path.join(derived, "SourcePackages"))
    candidates.append("/private/tmp/flowdown-deriveddata/SourcePackages")
    candidates.extend(
        sorted(
            glob.glob(
                os.path.expanduser(
                    "~/Library/Developer/Xcode/DerivedData/FlowDown-*/SourcePackages"
                )
            ),
            key=lambda path: os.path.getmtime(path),
            reverse=True,
        )
    )
    return candidates


def resolved_state(identity: str, source_packages: list[str]) -> dict | None:
    """Read the checkout state SwiftPM actually resolved for `identity`."""
    for directory in source_packages:
        state_file = os.path.join(directory, "workspace-state.json")
        if not os.path.isfile(state_file):
            state_file = directory if directory.endswith(".json") else None
        if not state_file or not os.path.isfile(state_file):
            continue
        try:
            with open(state_file) as handle:
                state = json.load(handle)
        except (OSError, ValueError):
            continue
        for dependency in state.get("object", {}).get("dependencies", []):
            if dependency.get("packageRef", {}).get("identity") != identity:
                continue
            checkout = dependency.get("state", {}).get("checkoutState")
            if not checkout:
                continue
            pin_state = {"revision": checkout["revision"]}
            if "version" in checkout:
                pin_state["version"] = checkout["version"]
            elif "branch" in checkout:
                pin_state["branch"] = checkout["branch"]
            return pin_state
    return None


def run(mode: str, config_path: str, source_packages: list[str]) -> int:
    with open(config_path) as handle:
        config = json.load(handle)

    failures: list[str] = []
    changed_files: list[str] = []

    for relative_path, required in config["files"].items():
        resolved_path = os.path.join(REPO_ROOT, relative_path)
        document, raw = load_resolved(resolved_path)
        pins = document["pins"]
        by_identity = {pin["identity"]: pin for pin in pins}
        dirty = False

        for requirement in required:
            identity = requirement["identity"]
            existing = by_identity.get(identity)

            if mode == "check":
                if existing is None:
                    failures.append(
                        f"{relative_path}: missing pin '{identity}' — {requirement['reason']}"
                    )
                continue

            state = (
                resolved_state(identity, source_packages)
                or (existing or {}).get("state")
                or requirement.get("fallbackState")
            )
            if state is None:
                failures.append(
                    f"{relative_path}: cannot restore '{identity}'; resolve packages first"
                )
                continue

            if existing is not None and existing.get("state") == state:
                continue

            if existing is None:
                pins.append(
                    {
                        "identity": identity,
                        "kind": requirement["kind"],
                        "location": requirement["location"],
                        "state": state,
                    }
                )
                log(f"{relative_path}: restored '{identity}' @ {state.get('version', state['revision'])}")
            else:
                existing["state"] = state
                log(f"{relative_path}: refreshed '{identity}' @ {state.get('version', state['revision'])}")
            dirty = True

        if not dirty:
            continue

        pins.sort(key=lambda pin: pin["identity"])
        updated = dump_resolved(document)
        if raw != dump_resolved(json.loads(raw)):
            log(f"{relative_path}: note — file was not in SwiftPM's format and has been normalized")
        with open(resolved_path, "w") as handle:
            handle.write(updated)
        changed_files.append(relative_path)

    if failures:
        for failure in failures:
            print(f"[required-pins] error: {failure}", file=sys.stderr)
        if mode == "check":
            print(
                "[required-pins] run `make package-resolve` (or "
                "`Resources/DevKit/scripts/required_package_pins.py fix`) and commit the result",
                file=sys.stderr,
            )
        return 1

    if mode == "check":
        log("all required pins present")
    elif not changed_files:
        log("all required pins already up to date")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["check", "fix"])
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument(
        "--source-packages",
        action="append",
        default=[],
        metavar="DIR",
        help="SourcePackages directory (or workspace-state.json) to read resolved versions from",
    )
    arguments = parser.parse_args()
    return run(arguments.mode, arguments.config, candidate_source_packages(arguments.source_packages))


if __name__ == "__main__":
    sys.exit(main())
