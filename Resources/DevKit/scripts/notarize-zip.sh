#!/bin/zsh

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <path-to-app> <output-zip-path>"
  exit 1
fi

APP_PATH="$1"
OUTPUT_ZIP="$2"
APP_DIR=$(dirname "$APP_PATH")
APP_NAME=$(basename "$APP_PATH")

if [[ ! -d "$APP_PATH" ]]; then
  echo "[-] app path does not exist: $APP_PATH"
  exit 1
fi

if [[ ! "$APP_PATH" =~ \.app$ ]]; then
  echo "[-] provided path is not a .app bundle: $APP_PATH"
  exit 1
fi

for required in CODE_SIGNING_IDENTITY NOTARIZE_KEYCHAIN_PROFILE; do
  if [[ -z "${(P)required:-}" ]]; then
    echo "[-] missing required env: $required"
    exit 1
  fi
done

SUBMIT_TMP_DIR=$(mktemp -d)
SUBMIT_ZIP="${SUBMIT_TMP_DIR}/${APP_NAME%.app}-submit.zip"

echo "[*] zipping app for notarization: $SUBMIT_ZIP"
pushd "$APP_DIR" >/dev/null
ditto -c -k --keepParent "$APP_NAME" "$SUBMIT_ZIP"
popd >/dev/null

if [[ ! -f "$SUBMIT_ZIP" ]]; then
  echo "[-] failed to create submit zip at $SUBMIT_ZIP"
  exit 1
fi

echo "[*] submitting app for notarization"
set +e
SUBMIT_OUTPUT=$(xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" \
  --wait \
  2>&1)
SUBMIT_EXIT=$?
set -e

echo "$SUBMIT_OUTPUT"

SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -n 1 | awk '{print $2}')

fetch_notary_log() {
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "[*] fetching notarization log for submission: $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" || true
  fi
}

if [[ "$SUBMIT_EXIT" -ne 0 ]]; then
  echo "[-] notarytool submit failed (exit ${SUBMIT_EXIT})"
  fetch_notary_log
  exit "$SUBMIT_EXIT"
fi

if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
  echo "[+] notarization accepted"
else
  echo "[-] notarization failed or timed out"
  fetch_notary_log
  exit 1
fi

echo "[*] stapling notarization ticket to app"
if ! xcrun stapler staple "$APP_PATH"; then
  echo "[-] failed to staple notarization ticket to app"
  exit 1
fi
echo "[+] app stapled successfully"

echo "[*] verifying staple"
if ! xcrun stapler validate "$APP_PATH"; then
  echo "[-] staple validation failed"
  exit 1
fi
echo "[+] staple validated successfully"

echo "[*] running spctl assessment"
if ! spctl --assess --type exec --verbose "$APP_PATH"; then
  echo "[-] spctl assessment failed"
  exit 1
fi
echo "[+] spctl assessment passed"

echo "[*] waiting 5s after spctl"
sleep 5

echo "[*] creating zip: $OUTPUT_ZIP"
mkdir -p "$(dirname "$OUTPUT_ZIP")"
pushd "$APP_DIR" >/dev/null
ditto -c -k --keepParent "$APP_NAME" "$OUTPUT_ZIP"
popd >/dev/null

if [[ ! -f "$OUTPUT_ZIP" ]]; then
  echo "[-] expected zip not found at $OUTPUT_ZIP"
  exit 1
fi

echo "[+] zip created at $OUTPUT_ZIP"

