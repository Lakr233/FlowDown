#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path

APPLICATIONS_DIR = Path("/Applications")


def log(message: str) -> None:
    print(f"[select-xcode] {message}")


def version_key(value: str) -> tuple:
    parts = []
    for segment in value.split('.'):
        parts.append(int(segment) if segment.isdigit() else segment)
    return tuple(parts)


def discover_xcodes() -> list[Path]:
    if not APPLICATIONS_DIR.is_dir():
        return []
    bundles = []
    for path in APPLICATIONS_DIR.iterdir():
        if not path.is_dir() or not path.name.startswith("Xcode") or path.suffix != ".app":
            continue
        if path.is_symlink():
            log(f"skipping {path} (symlink)")
            continue
        if "beta" in path.name.lower():
            log(f"skipping {path} (beta build)")
            continue
        bundles.append(path)
    return sorted(bundles, key=lambda p: p.name)


def read_metadata(bundle: Path):
    plist_path = bundle / "Contents/Info.plist"
    if not plist_path.is_file():
        log(f"skipping {bundle} (no Info.plist)")
        return None
    try:
        with plist_path.open("rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:  # noqa: BLE001
        log(f"skipping {bundle} (plist error: {exc})")
        return None

    version = str(plist.get("CFBundleShortVersionString", "")).strip()
    build = str(plist.get("CFBundleVersion", "")).strip()

    if not version:
        log(f"skipping {bundle} (no version)")
        return None

    return {
        "path": bundle,
        "version": version,
        "build": build,
        "sort_key": (version_key(version), version_key(build) if build else ()),
    }


def select_newest(candidates):
    return sorted(candidates, key=lambda item: item["sort_key"])[-1]


def main() -> int:
    import os

    bundles = discover_xcodes()
    if not bundles:
        print("[-] no Xcode installations found under /Applications", file=sys.stderr)
        return 1

    candidates = [meta for meta in (read_metadata(bundle) for bundle in bundles) if meta]
    if not candidates:
        print("[-] no Xcode installations with readable versions found", file=sys.stderr)
        return 1

    xcode_version = os.environ.get("XCODE_VERSION", "").strip()
    if xcode_version:
        filtered = [c for c in candidates if c["version"].startswith(xcode_version)]
        if not filtered:
            print(
                f"[-] no Xcode matching version prefix '{xcode_version}' "
                f"(available: {', '.join(c['version'] for c in candidates)})",
                file=sys.stderr,
            )
            return 1
        log(f"filtering to Xcode versions matching '{xcode_version}' ({len(filtered)} found)")
        candidates = filtered

    newest = select_newest(candidates)

    xcode_path = newest["path"]
    developer_dir = xcode_path / "Contents/Developer"
    if not developer_dir.is_dir():
        print(f"[-] developer directory missing for {xcode_path}", file=sys.stderr)
        return 1

    log(f"selecting Xcode {newest['version']} (build {newest['build']}) at {xcode_path}")

    subprocess.run(["sudo", "xcode-select", "-s", str(developer_dir)], check=True)
    selected = subprocess.run(["xcode-select", "-p"], check=True, capture_output=True, text=True)
    log(f"xcode-select set to {selected.stdout.strip()}")
    subprocess.run(["xcodebuild", "-version"], check=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
