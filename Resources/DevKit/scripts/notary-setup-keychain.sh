#!/bin/zsh

set -euo pipefail

# Usage:
#   NOTARY_TOOLBOX_ZIP_BASE64=... NOTARY_TOOLBOX_PASSWORD=... \
#     ./notary-setup-keychain.sh <github_output_file> <github_env_file>
# or pre-supply KEYCHAIN_DB and KEYCHAIN_PASSWORD to reuse an existing keychain.
#
# The script will:
# - Decode the provided base64 zip into .build/keychain
# - Locate and unlock the keychain, extract signing identities and notary profile
# - Emit outputs (for workflow) and append exports (for local use) without removing the toolbox

OUTPUT_FILE="${1:-}"
ENV_FILE="${2:-}"

log() {
  echo "[notary-setup] $*"
}

fatal() {
  echo "[-] $*" >&2
  exit 1
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
TOOLBOX_DIR="${PROJECT_ROOT}/.build/keychain"

KEYCHAIN_DB="${KEYCHAIN_DB-}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD-}"

if [[ -z "$KEYCHAIN_DB" ]]; then
  if [[ -z "${NOTARY_TOOLBOX_ZIP_BASE64:-}" ]]; then
    fatal "NOTARY_TOOLBOX_ZIP_BASE64 is not set"
  fi
  if [[ -z "${NOTARY_TOOLBOX_PASSWORD:-}" ]]; then
    fatal "NOTARY_TOOLBOX_PASSWORD is not set"
  fi

  mkdir -p "$TOOLBOX_DIR"
  ZIP_PATH="${TOOLBOX_DIR}/toolbox.zip"
  UNPACK_DIR="${TOOLBOX_DIR}/unpacked"
  rm -rf "$UNPACK_DIR"

  log "decoding toolbox zip to ${ZIP_PATH}"
  echo "${NOTARY_TOOLBOX_ZIP_BASE64}" | base64 -D > "$ZIP_PATH"

  log "unpacking toolbox into ${UNPACK_DIR}"
  unzip -qo "$ZIP_PATH" -d "$UNPACK_DIR"

  KEYCHAIN_PATH=$(find "$UNPACK_DIR" -type f -name "*.keychain*" | head -n 1)
  if [[ -z "$KEYCHAIN_PATH" ]]; then
    fatal "no keychain file found after unpacking"
  fi

  KEYCHAIN_DB=$(realpath "$KEYCHAIN_PATH")
  KEYCHAIN_PASSWORD="$NOTARY_TOOLBOX_PASSWORD"
  log "using keychain at: $KEYCHAIN_DB"
else
  if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
    fatal "KEYCHAIN_PASSWORD is not set"
  fi
  KEYCHAIN_DB=$(realpath "$KEYCHAIN_DB")
  log "using existing keychain: $KEYCHAIN_DB"
fi

KEYCHAIN_TIMEOUT="${NOTARY_KEYCHAIN_TIMEOUT:-86400}"

log "adding keychain to user search list"
CURRENT_KEYCHAINS=()
while IFS= read -r line; do
  line=$(echo "$line" | tr -d '"' | xargs)
  [[ -n "$line" ]] && CURRENT_KEYCHAINS+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN_DB" "${CURRENT_KEYCHAINS[@]}"

log "default user keychain: $(security default-keychain -d user | tr -d '"')"
log "unlocking keychain"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_DB"

log "setting keychain timeout to ${KEYCHAIN_TIMEOUT}s"
security set-keychain-settings -t "$KEYCHAIN_TIMEOUT" -l "$KEYCHAIN_DB"

log "reading signing identity"
CODE_SIGNING_CONTENTS=$(security find-identity -v -p codesigning "$KEYCHAIN_DB")
DEVELOPER_ID_LINE=$(echo "$CODE_SIGNING_CONTENTS" | grep "Developer ID Application" | head -n 1)
CODE_SIGNING_IDENTITY=$(echo "$DEVELOPER_ID_LINE" | sed 's/.*"\(.*\)".*/\1/')
CODE_SIGNING_IDENTITY_HASH=$(echo "$DEVELOPER_ID_LINE" | awk '{print $2}')
CODE_SIGNING_TEAM=$(echo "$DEVELOPER_ID_LINE" | sed 's/.*(\(.*\)).*/\1/')

if [[ -z "$CODE_SIGNING_IDENTITY" || -z "$CODE_SIGNING_IDENTITY_HASH" || -z "$CODE_SIGNING_TEAM" ]]; then
  fatal "failed to extract signing identity/team from keychain"
fi

log "identity: $CODE_SIGNING_IDENTITY"
log "identity hash: $CODE_SIGNING_IDENTITY_HASH"
log "team: $CODE_SIGNING_TEAM"

log "reading notary profile"
NOTARIZE_KEYCHAIN_PROFILE=$(
  security dump-keychain -r "$KEYCHAIN_DB" | \
  strings | \
  grep "com.apple.gke.notary.tool.saved-creds" | \
  head -n 1 | \
  awk -F. '{print $NF}' | \
  tr -d '"'
)

if [[ -z "$NOTARIZE_KEYCHAIN_PROFILE" ]]; then
  fatal "failed to extract notary profile from keychain"
fi

log "notary profile: $NOTARIZE_KEYCHAIN_PROFILE"

# Prefer using the hash as signing identity for deterministic behavior
CODE_SIGNING_IDENTITY="$CODE_SIGNING_IDENTITY_HASH"

emit() {
  local file="$1"
  local key="$2"
  local value="$3"
  if [[ -n "$file" ]]; then
    echo "${key}=${value}" >> "$file"
  fi
}

emit "$OUTPUT_FILE" "keychain_db" "$KEYCHAIN_DB"
emit "$OUTPUT_FILE" "code_signing_identity" "$CODE_SIGNING_IDENTITY"
emit "$OUTPUT_FILE" "code_signing_team" "$CODE_SIGNING_TEAM"
emit "$OUTPUT_FILE" "notarize_keychain_profile" "$NOTARIZE_KEYCHAIN_PROFILE"

emit "$ENV_FILE" "KEYCHAIN_DB" "$KEYCHAIN_DB"
emit "$ENV_FILE" "CODE_SIGNING_IDENTITY" "$CODE_SIGNING_IDENTITY"
emit "$ENV_FILE" "CODE_SIGNING_TEAM" "$CODE_SIGNING_TEAM"
emit "$ENV_FILE" "NOTARIZE_KEYCHAIN_PROFILE" "$NOTARIZE_KEYCHAIN_PROFILE"

log "setup completed successfully (toolbox kept at ${TOOLBOX_DIR})"

