#!/bin/zsh

set -euo pipefail

OUTPUT_FILE="${1:-}"

log() {
  echo "[notary-action] $*"
}

fatal() {
  echo "[-] $*" >&2
  exit 1
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
cd "$PROJECT_ROOT"

ARCHIVE_PATH="${PROJECT_ROOT}/BuildArtifacts/FlowDown-macos.xcarchive"
RESULT_BUNDLE="${PROJECT_ROOT}/BuildArtifacts/macos-notary.xcresult"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/FlowDown.app"
ZIP_OUTPUT="${NOTARIZE_ZIP_OUTPUT:?NOTARIZE_ZIP_OUTPUT is required}"

if [[ -z "${ENABLE_NOTARIZE:-}" ]]; then
  if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
    ENABLE_NOTARIZE=1
  else
    ENABLE_NOTARIZE=0
  fi
fi

REQUIRED_VARS=(
  CODE_SIGNING_IDENTITY
  KEYCHAIN_DB
  NOTARY_PROVISION_PROFILE_PATH
  NOTARIZE_KEYCHAIN_PROFILE
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${(P)var:-}" ]]; then
    fatal "${var} is required for notarization workflow"
  fi
done

if [[ "$ENABLE_NOTARIZE" == "1" && -z "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
  fatal "NOTARIZE_KEYCHAIN_PROFILE is required when ENABLE_NOTARIZE=1"
fi

log "selecting newest Xcode"
"${SCRIPT_DIR}/select_newest_xcode.sh"

log "ensuring Metal toolchain"
xcodebuild -downloadComponent MetalToolchain || true

log "resolving packages"
"${SCRIPT_DIR}/resolve-packages.sh"

log "archiving unsigned macOS build"
"${SCRIPT_DIR}/xcodebuild-archive-macos.sh"

if [[ ! -d "$APP_PATH" ]]; then
  fatal "app not found at $APP_PATH"
fi

log "signing archived macOS build"
env \
  CODE_SIGNING_IDENTITY="$CODE_SIGNING_IDENTITY" \
  KEYCHAIN_DB="$KEYCHAIN_DB" \
  EMBED_PROVISION_PROFILE="$NOTARY_PROVISION_PROFILE_PATH" \
  "${SCRIPT_DIR}/codesign-macos.sh" "$APP_PATH"

if [[ "$ENABLE_NOTARIZE" != "1" ]]; then
  log "notarization disabled; signed archive available at ${ARCHIVE_PATH}"
  exit 0
fi

log "running notarization"
env \
  CODE_SIGNING_IDENTITY="$CODE_SIGNING_IDENTITY" \
  NOTARIZE_KEYCHAIN_PROFILE="$NOTARIZE_KEYCHAIN_PROFILE" \
  "${SCRIPT_DIR}/notarize-zip.sh" "$APP_PATH" "$ZIP_OUTPUT"

if [[ ! -f "$ZIP_OUTPUT" ]]; then
  fatal "expected zip not found at $ZIP_OUTPUT"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "zip_path=${ZIP_OUTPUT}" >> "$OUTPUT_FILE"
fi

log "archive: ${ARCHIVE_PATH}"
log "xcresult: ${RESULT_BUNDLE}"
log "notarized zip: ${ZIP_OUTPUT}"
log "workflow completed successfully"
