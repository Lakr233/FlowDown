#!/bin/zsh

set -euo pipefail

# Re-sign a built macOS (Catalyst) app after an unsigned archive.
# Env:
#   CODE_SIGNING_IDENTITY (required)
#   KEYCHAIN_DB (optional)
#   ENTITLEMENTS_PATH (optional; default FlowDown/Resources/Entitlements/Entitlements-Catalyst.entitlements)
#   EMBED_PROVISION_PROFILE (required .provisionprofile to embed)
# Usage:
#   ./codesign-macos.sh /path/to/FlowDown.app

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "[-] app bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "${CODE_SIGNING_IDENTITY:-}" ]]; then
  echo "[-] CODE_SIGNING_IDENTITY is required" >&2
  exit 1
fi

if [[ -z "${EMBED_PROVISION_PROFILE:-}" || ! -f "$EMBED_PROVISION_PROFILE" ]]; then
  echo "[-] provisioning profile not found: ${EMBED_PROVISION_PROFILE:-<unset>}" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
DEFAULT_ENTITLEMENTS="${PROJECT_ROOT}/FlowDown/Resources/Entitlements/Entitlements-Catalyst.entitlements"
SOURCE_ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$DEFAULT_ENTITLEMENTS}"

if [[ ! -f "$SOURCE_ENTITLEMENTS_PATH" ]]; then
  echo "[-] entitlements file not found: $SOURCE_ENTITLEMENTS_PATH" >&2
  exit 1
fi

echo "[i] using keychain at ${KEYCHAIN_DB:-<default>}"
echo "[i] source entitlements: ${SOURCE_ENTITLEMENTS_PATH}"

echo "[*] stripping existing signatures and profiles"
find "$APP_PATH" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name "embedded.provisionprofile" -type f -exec rm -f {} + 2>/dev/null || true

BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_PATH}/Contents/Info.plist")
if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
  echo "[-] failed to read bundle identifier" >&2
  exit 1
fi

PROFILE_PLIST=$(mktemp)
RESOLVED_ENTITLEMENTS=$(mktemp)
trap 'rm -f "$PROFILE_PLIST" "$RESOLVED_ENTITLEMENTS"' EXIT
security cms -D -i "$EMBED_PROVISION_PROFILE" > "$PROFILE_PLIST"

PROFILE_APPLICATION_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PROFILE_PLIST")
PROFILE_TEAM_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$PROFILE_PLIST")
PROFILE_GET_TASK_ALLOW=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:get-task-allow" "$PROFILE_PLIST")
if [[ "$PROFILE_APPLICATION_IDENTIFIER" != "${PROFILE_TEAM_IDENTIFIER}.${BUNDLE_IDENTIFIER}" ]]; then
  echo "[-] provisioning profile does not match ${BUNDLE_IDENTIFIER}" >&2
  exit 1
fi
if [[ "$PROFILE_GET_TASK_ALLOW" != "false" ]]; then
  echo "[-] provisioning profile allows debugging" >&2
  exit 1
fi

/usr/bin/sed \
  -e 's|$(APS_ENVIRONMENT)|production|g' \
  -e 's|$(CLOUDKIT_CONTAINER_ENVIRONMENT)|Production|g' \
  -e 's|$(CLOUDKIT_SYNC_CONTAINER_IDENTIFIER)|iCloud.'"${BUNDLE_IDENTIFIER}"'.sync|g' \
  "$SOURCE_ENTITLEMENTS_PATH" > "$RESOLVED_ENTITLEMENTS"

if /usr/bin/grep -Fq '$(' "$RESOLVED_ENTITLEMENTS"; then
  echo "[-] unresolved build setting in entitlements" >&2
  exit 1
fi

/usr/libexec/PlistBuddy \
  -c "Add :application-identifier string ${PROFILE_APPLICATION_IDENTIFIER}" \
  -c "Add :com.apple.application-identifier string ${PROFILE_APPLICATION_IDENTIFIER}" \
  -c "Add :com.apple.developer.team-identifier string ${PROFILE_TEAM_IDENTIFIER}" \
  -c "Add :get-task-allow bool ${PROFILE_GET_TASK_ALLOW}" \
  "$RESOLVED_ENTITLEMENTS"
plutil -lint "$RESOLVED_ENTITLEMENTS"

echo "[*] embedding provision profile ${EMBED_PROVISION_PROFILE}"
cp "$EMBED_PROVISION_PROFILE" "${APP_PATH}/Contents/embedded.provisionprofile"

SCANNER="${SCRIPT_DIR}/apple-resign-scan.py"
if [[ ! -f "$SCANNER" ]]; then
  echo "[-] scanner not found: $SCANNER" >&2
  exit 1
fi

FILE_CANDIDATES=()
while IFS= read -r line; do
  FILE_CANDIDATES+=("$line")
done < <(python3 "$SCANNER" "$APP_PATH")
echo "[*] found ${#FILE_CANDIDATES[@]} candidates to sign"

sign_item() {
  local item_path="$1"
  local args=(
    --force
    --timestamp
    --generate-entitlement-der
    --strip-disallowed-xattrs
    --options runtime
    --sign "$CODE_SIGNING_IDENTITY"
  )
  if [[ -n "${KEYCHAIN_DB:-}" ]]; then
    args+=(--keychain "$KEYCHAIN_DB")
  fi
  if [[ "$item_path" == *.app ]]; then
    echo "[+] signing $(basename "$item_path") with entitlements"
    args+=(--entitlements "$RESOLVED_ENTITLEMENTS")
  else
    echo "[+] signing $(basename "$item_path")"
  fi
  xattr -cr "$item_path" || true
  /usr/bin/codesign "${args[@]}" "$item_path"
}

for ITEM in "${FILE_CANDIDATES[@]}"; do
  sign_item "$ITEM"
done

echo "[*] verifying..."
VERIFY_ARGS=(--verify --deep --strict)
if [[ -n "${KEYCHAIN_DB:-}" ]]; then
  VERIFY_ARGS+=(--keychain "$KEYCHAIN_DB")
fi
/usr/bin/codesign "${VERIFY_ARGS[@]}" "$APP_PATH"

echo "[+] codesign completed for ${APP_PATH}"
