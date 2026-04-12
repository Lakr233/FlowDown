#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
FDMODEL_PATH=$(find "$REPO_ROOT" -maxdepth 1 -name '*.fdmodel' | sort | head -n 1)
PROFILE="$HOME/.zprofile"
SUPPORT_DIR="$HOME/.testing"
API_KEY_FILE="$SUPPORT_DIR/openrouter.sk"
BEGIN_MARKER="# >>> flowdown openrouter api key >>>"
END_MARKER="# <<< flowdown openrouter api key <<<"

if [[ -z "$FDMODEL_PATH" ]]; then
    echo "[-] no root .fdmodel found" >&2
    exit 1
fi

TOKEN=$(/usr/libexec/PlistBuddy -c "Print token" "$FDMODEL_PATH" 2>/dev/null || true)

if [[ -z "$TOKEN" ]]; then
    echo "[-] no token found in $FDMODEL_PATH" >&2
    exit 1
fi

mkdir -p "$SUPPORT_DIR"
printf '%s\n' "$TOKEN" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"

if ! grep -Fq "$BEGIN_MARKER" "$PROFILE" 2>/dev/null; then
    {
        echo ""
        echo "$BEGIN_MARKER"
        echo "if [[ -z \"\${OPENROUTER_API_KEY:-}\" ]]; then"
        echo "  export OPENROUTER_API_KEY=\"\$(/usr/libexec/PlistBuddy -c 'Print token' '$FDMODEL_PATH' 2>/dev/null || true)\""
        echo "fi"
        echo "$END_MARKER"
    } >> "$PROFILE"
fi

echo "[+] configured $PROFILE"
echo "[+] wrote $API_KEY_FILE"
