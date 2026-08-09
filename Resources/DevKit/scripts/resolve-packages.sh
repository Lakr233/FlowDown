#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORKSPACE="${WORKSPACE:-FlowDown.xcworkspace}"
SCHEME="${SCHEME:-FlowDown}"
PACKAGE_RESOLVED_FILES=(
  Frameworks/*/Package.resolved
)

echo "[resolve-packages] workspace: $WORKSPACE"
echo "[resolve-packages] scheme: $SCHEME"

# The CUDA-plugin strip rewrites the resolved mlx-swift manifest in place, and
# the patched manifest describes a smaller dependency graph than the real one.
# Resolve against the pristine manifest and re-apply the strip afterwards.
"$SCRIPT_DIR/strip_mlx_cuda_plugin.sh" --restore

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

# Xcode 27's resolver prunes pins that no built target links, but Xcode Cloud's
# older toolchain rejects a Package.resolved that is missing them. Put them back
# before anyone commits the file.
"$SCRIPT_DIR/required_package_pins.py" fix

"$SCRIPT_DIR/strip_mlx_cuda_plugin.sh"

echo "[resolve-packages] done"
