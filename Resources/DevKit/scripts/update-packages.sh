#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

WORKSPACE="${WORKSPACE:-FlowDown.xcworkspace}"
SCHEME="${SCHEME:-FlowDown}"
WORKSPACE_RESOLVED="FlowDown.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGE_RESOLVED_FILES=(
    Frameworks/*/Package.resolved
)

# Resolve against the pristine mlx-swift manifest; the CUDA-plugin strip hides
# part of the dependency graph. See strip_mlx_cuda_plugin.sh.
"$SCRIPT_DIR/strip_mlx_cuda_plugin.sh" --restore

echo "[+] upgrading workspace packages..."
rm -f "$WORKSPACE_RESOLVED"
xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -resolvePackageDependencies \
    | xcbeautify --is-ci --disable-colored-output --disable-logging

for file in "${PACKAGE_RESOLVED_FILES[@]}"; do
    package_path="$(dirname "$file")"
    echo "[+] upgrading $package_path packages..."
    swift package --package-path "$package_path" update
done

# Rebuilding the resolved file from scratch always drops the pins that Xcode 27
# prunes and Xcode Cloud requires. See required-package-pins.json.
"$SCRIPT_DIR/required_package_pins.py" fix

"$SCRIPT_DIR/strip_mlx_cuda_plugin.sh"

echo "[+] completed successfully"
