#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)

if [[ -z "${FIREWORKS_API_KEY:-}" ]]; then
    echo "[-] FIREWORKS_API_KEY is required" >&2
    exit 1
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID:-}" ]]; then
    echo "[-] FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID is required" >&2
    exit 1
fi

echo "[+] recording online e2e fixtures with curl-backed capture server"

cd "$REPO_ROOT"

FLOWDOWN_ONLINE_E2E_RECORD=1 \
    FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
    FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID="$FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID" \
    make test-online-e2e
