#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE_MODE="${1:-all}"
CATALYST_ARCHIVE_DESTINATION='generic/platform=macOS,variant=Mac Catalyst'

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

if [[ -d .git ]] && [[ -d FlowDown.xcworkspace ]]; then
    echo "[*] found project root: $(pwd)"
else
    echo "[!] could not find project root"
    exit 1
fi

PROJECT_ROOT=$(pwd)

# Resolve into the default DerivedData the archive builds from and strip the
# mlx-swift CUDA plugin, before anything is bumped or committed. Any resolve
# drift then fails the clean check below.
./Resources/DevKit/scripts/resolve-packages.sh

if [[ -n $(git status --porcelain) ]]; then
    echo "[!] git is not clean"
    exit 1
fi

./Resources/DevKit/scripts/bump.version.sh
git add -A
git commit -m "Archive Commit $(date)"

./Resources/DevKit/scripts/scan.license.sh

archive_ios() {
    XCBUILD_LABEL=archive-ios ./Resources/DevKit/scripts/run_xcodebuild.sh \
        -workspace FlowDown.xcworkspace \
        -scheme FlowDown \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$PROJECT_ROOT/.build/FlowDown.xcarchive" \
        archive

    echo "[*] registering FlowDown.xcarchive in Xcode Organizer..."
    open "$PROJECT_ROOT/.build/FlowDown.xcarchive" -g
}

archive_macos() {
    XCBUILD_LABEL=archive-macos ./Resources/DevKit/scripts/run_xcodebuild.sh \
        -workspace FlowDown.xcworkspace \
        -scheme FlowDown \
        -configuration Release \
        -destination "$CATALYST_ARCHIVE_DESTINATION" \
        -archivePath "$PROJECT_ROOT/.build/FlowDown-macOS.xcarchive" \
        archive

    echo "[*] registering FlowDown-macOS.xcarchive in Xcode Organizer..."
    open "$PROJECT_ROOT/.build/FlowDown-macOS.xcarchive" -g
}

case "$ARCHIVE_MODE" in
    all)
        archive_ios
        archive_macos
        ;;
    ios)
        archive_ios
        ;;
    macos)
        archive_macos
        ;;
    *)
        echo "[!] unknown archive mode: $ARCHIVE_MODE"
        exit 1
        ;;
esac

echo "[*] done"

osascript -e 'display notification "FlowDown has completed archive process." with title "Build Success"'
