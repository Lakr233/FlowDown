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

# Fails in a second with a precise reason, rather than after a multi-minute
# resolve that ends in xcodebuild's generic out-of-date-resolved-file error.
"${REPO_ROOT}/Resources/DevKit/scripts/required_package_pins.py" check || {
  echo "[!] Package.resolved is missing a pin Xcode Cloud's resolver requires." >&2
  echo "[!] Fix on a Mac with: make package-resolve && git commit FlowDown.xcworkspace" >&2
  echo "[!] Attempting to resolve anyway." >&2
}

# Pre-resolve swift packages into the directory Xcode Cloud builds from, then
# strip the CUDA build-tool plugin from mlx-swift (it breaks macOS archives
# with "Multiple commands produce .../UninstalledProducts/macosx/encuda").
# The build reuses these checkouts because the pinned revisions match, so the
# patch survives into the archive action.
resolve_packages() {
  xcodebuild -resolvePackageDependencies \
    -workspace "${REPO_ROOT}/FlowDown.xcworkspace" \
    -scheme "${SCHEME}" \
    -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"
}

echo "[+] resolving packages into ${SOURCE_PACKAGES}"
if ! resolve_packages; then
  # Xcode Cloud disables automatic package resolution, so any pin the local
  # toolchain pruned is a hard failure here. Rather than lose a release to a
  # resolver disagreement, let the resolver add the missing pin and continue --
  # the committed file still constrains every version it does list.
  echo "[!] package resolution failed; retrying with automatic resolution enabled" >&2
  echo "[!] this means Package.resolved is out of date -- commit a fresh resolve" >&2
  defaults write com.apple.dt.Xcode IDEDisableAutomaticPackageResolution -bool NO
  resolve_packages
fi

"${REPO_ROOT}/Resources/DevKit/scripts/strip_mlx_cuda_plugin.sh" "${SOURCE_PACKAGES}"
