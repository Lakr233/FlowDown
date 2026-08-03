#!/bin/zsh

set -euo pipefail

WORKSPACE="${WORKSPACE:-FlowDown.xcworkspace}"
SCHEME="${SCHEME:-FlowDown}"
PACKAGE_RESOLVED_FILES=(
  Frameworks/*/Package.resolved
)

echo "[resolve-packages] workspace: $WORKSPACE"
echo "[resolve-packages] scheme: $SCHEME"

# The CUDA-plugin strip patches the resolved mlx-swift checkout in place, and
# the patched manifest drops swift-argument-parser from the dependency graph.
# Resolving against it records a Package.resolved that a pristine CI clone
# rejects as out of date. Restore the pristine manifest before resolving; the
# strip below re-applies the patch afterwards.
for manifest in "$HOME"/Library/Developer/Xcode/DerivedData/FlowDown-*/SourcePackages/checkouts/mlx-swift/Package.swift(N); do
  if git -C "$(dirname "$manifest")" checkout -- Package.swift 2>/dev/null; then
    echo "[resolve-packages] restored pristine manifest: $manifest"
  fi
done

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -resolvePackageDependencies \
  | xcbeautify --is-ci --disable-colored-output --disable-logging

for file in "${PACKAGE_RESOLVED_FILES[@]}"; do
  package_path="$(dirname "$file")"
  echo "[resolve-packages] package: $package_path"
  swift package --package-path "$package_path" resolve
done

"$(cd "$(dirname "$0")" && pwd)/strip_mlx_cuda_plugin.sh"

echo "[resolve-packages] done"
