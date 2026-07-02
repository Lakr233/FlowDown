#!/bin/zsh

set -euo pipefail

WORKSPACE="${WORKSPACE:-FlowDown.xcworkspace}"
SCHEME="${SCHEME:-FlowDown}"
PACKAGE_RESOLVED_FILES=(
  Frameworks/*/Package.resolved
)

echo "[resolve-packages] workspace: $WORKSPACE"
echo "[resolve-packages] scheme: $SCHEME"

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

echo "[resolve-packages] done"
