#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

if [[ -d .git ]] && [[ -d FlowDown.xcworkspace ]]; then
    echo "[+] found project root: $(pwd)"
else
    echo "[-] could not find project root"
    exit 1
fi

VERSION_CONFIG="FlowDown/Configuration/Version.xcconfig"

# the targets carry $(inherited), so this file is the only build number that
# exists and agvtool cannot read it
BUILD_NUMBER=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);$/\1/p' "$VERSION_CONFIG")

if [[ -z "$BUILD_NUMBER" ]]; then
    echo "[-] could not read CURRENT_PROJECT_VERSION from $VERSION_CONFIG"
    exit 1
fi

echo "[+] current build number: $BUILD_NUMBER"
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))

sed -i '' "s/^CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};$/CURRENT_PROJECT_VERSION = ${NEW_BUILD_NUMBER};/" "$VERSION_CONFIG"

echo "[+] incremented build number to: $NEW_BUILD_NUMBER"
