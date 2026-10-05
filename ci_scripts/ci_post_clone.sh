#!/bin/zsh

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
SOURCE_PACKAGES="${CI_DERIVED_DATA_PATH:-/Volumes/workspace/DerivedData}/SourcePackages"
SCHEME="${CI_XCODE_SCHEME:-FlowDown}"

# Package resolution here is toolchain-sensitive, and Xcode Cloud's toolchain is
# not the one anyone resolves with locally. Record which one ran.
echo "[+] toolchain"
xcodebuild -version || true
swift --version 2>&1 | head -2 || true

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
echo "[+] package plugin validation disabled"

# ChatClientKit declares mlx-swift-lm as a remote branch dependency; the
# workspace overrides it with the submodule. A missing submodule silently
# changes the graph instead of failing, so check before resolving.
for submodule in Frameworks/ChatClientKit Frameworks/mlx-swift-lm; do
  if [[ ! -f "${REPO_ROOT}/${submodule}/Package.swift" ]]; then
    echo "[!] submodule not checked out: ${submodule}" >&2
    echo "[!] Xcode Cloud must clone submodules for this workspace to resolve." >&2
    exit 1
  fi
done
echo "[+] submodules present"

# Pre-resolve swift packages into the directory Xcode Cloud builds from, so a
# resolver disagreement surfaces here with a fallback instead of failing the
# build action. The build reuses these checkouts because the pins match.
resolve_packages() {
  xcodebuild -resolvePackageDependencies \
    -workspace "${REPO_ROOT}/FlowDown.xcworkspace" \
    -scheme "${SCHEME}" \
    -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"
}

echo "[+] resolving packages into ${SOURCE_PACKAGES}"
if ! resolve_packages; then
  # Xcode Cloud disables automatic package resolution, so a pin its older
  # toolchain expects but the local one left out is a hard failure here. Rather
  # than lose a release to a resolver disagreement, let the resolver add the
  # missing pin and continue -- the committed file still constrains every
  # version it does list.
  echo "[!] package resolution failed; retrying with automatic resolution enabled" >&2
  echo "[!] this means Package.resolved is out of date -- commit a fresh resolve" >&2
  defaults write com.apple.dt.Xcode IDEDisableAutomaticPackageResolution -bool NO
  resolve_packages
fi
