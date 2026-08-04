#!/bin/zsh

set -euo pipefail

# Archives FlowDown macOS (Catalyst) unsigned with xcbeautify output.
# Signing is performed separately by codesign-macos.sh.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Prefer the git toplevel, but fall back to walking upward until we find the workspace.
if PROJECT_ROOT_CANDIDATE=$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null); then
  PROJECT_ROOT="$PROJECT_ROOT_CANDIDATE"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

SEARCH_ROOT="$PROJECT_ROOT"
while [[ "$SEARCH_ROOT" != "/" && ! -e "$SEARCH_ROOT/FlowDown.xcworkspace" ]]; do
  SEARCH_ROOT=$(dirname "$SEARCH_ROOT")
done

if [[ ! -e "$SEARCH_ROOT/FlowDown.xcworkspace" ]]; then
  echo "[-] FlowDown.xcworkspace not found from $SCRIPT_DIR" >&2
  exit 1
fi

PROJECT_ROOT="$SEARCH_ROOT"

cd "$PROJECT_ROOT"

WORKSPACE="FlowDown.xcworkspace"
SCHEME="FlowDown"
ARCHIVE_PATH="${PROJECT_ROOT}/BuildArtifacts/FlowDown-macos.xcarchive"
RESULT_BUNDLE="${PROJECT_ROOT}/BuildArtifacts/macos-notary.xcresult"

mkdir -p "${PROJECT_ROOT}/BuildArtifacts"

echo "[*] archive path: ${ARCHIVE_PATH}"
echo "[*] result bundle: ${RESULT_BUNDLE}"
echo "[i] code signing disabled during archive"

ARGS=(
  -workspace "$WORKSPACE"
  -scheme "$SCHEME"
  -configuration Release
  -destination 'platform=macOS,variant=Mac Catalyst'
  archive
  -archivePath "$ARCHIVE_PATH"
  -resultBundlePath "$RESULT_BUNDLE"
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  PROVISIONING_PROFILE_SPECIFIER=""
  -skipPackagePluginValidation
  -skipMacroValidation
)

echo "[*] running xcodebuild (xcbeautify)..."
xcodebuild "${ARGS[@]}" | xcbeautify --is-ci --disable-colored-output --disable-logging

echo "[+] archive generated at $ARCHIVE_PATH"
echo "[+] xcresult at $RESULT_BUNDLE"
