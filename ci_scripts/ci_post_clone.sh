#!/bin/zsh

set -euo pipefail

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES

echo "[+] package plugin validation disabled"

# Pre-resolve swift packages into the directory Xcode Cloud builds from, then
# strip the CUDA build-tool plugin from mlx-swift (it breaks macOS archives
# with "Multiple commands produce .../UninstalledProducts/macosx/encuda").
# The build reuses these checkouts because the pinned revisions match, so the
# patch survives into the archive action.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
SOURCE_PACKAGES="${CI_DERIVED_DATA_PATH:-/Volumes/workspace/DerivedData}/SourcePackages"

echo "[+] resolving packages into ${SOURCE_PACKAGES}"
xcodebuild -resolvePackageDependencies \
  -workspace "${REPO_ROOT}/FlowDown.xcworkspace" \
  -scheme "${CI_XCODE_SCHEME:-FlowDown}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}"

"${REPO_ROOT}/Resources/DevKit/scripts/strip_mlx_cuda_plugin.sh" "${SOURCE_PACKAGES}"
