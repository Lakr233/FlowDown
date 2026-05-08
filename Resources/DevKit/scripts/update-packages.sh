#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

WORKSPACE="${WORKSPACE:-FlowDown.xcworkspace}"
SCHEME="${SCHEME:-FlowDown}"
WORKSPACE_RESOLVED="FlowDown.xcworkspace/xcshareddata/swiftpm/Package.resolved"

echo "[+] upgrading workspace packages..."
rm -f "$WORKSPACE_RESOLVED"
xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -resolvePackageDependencies \
    | xcbeautify --is-ci --disable-colored-output --disable-logging

echo "[+] upgrading storage packages..."
swift package --package-path Frameworks/Storage update

echo "[+] completed successfully"
