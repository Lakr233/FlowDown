#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
DERIVED_DATA="${DERIVED_DATA:-/private/tmp/flowdown-online-e2e-deriveddata}"
BUILD_HOME="$DERIVED_DATA/home"
XDG_CACHE_HOME="$DERIVED_DATA/xdg-cache"
MODULE_CACHE="$DERIVED_DATA/ModuleCache.noindex"
E2E_SUPPORT_DIR="/tmp/flowdown-online-e2e"
ENABLE_MARKER="$E2E_SUPPORT_DIR/flowdown_e2e_enabled"
RUNTIME_ENDPOINT_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.endpoint"
FIXTURE_DIR="$REPO_ROOT/Resources/DevKit/fixtures/online_e2e"
SERVER_PID=""
SERVER_MODE="replay"
SERVER_ARGS=()

if [[ "${FLOWDOWN_ONLINE_E2E_RECORD:-0}" == "1" ]]; then
    SERVER_MODE="record"
    if [[ -z "${FIREWORKS_API_KEY:-}" ]]; then
        echo "[-] FIREWORKS_API_KEY is required when FLOWDOWN_ONLINE_E2E_RECORD=1" >&2
        exit 1
    fi
    if [[ -z "${FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID:-}" ]]; then
        echo "[-] FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID is required when FLOWDOWN_ONLINE_E2E_RECORD=1" >&2
        exit 1
    fi
    SERVER_ARGS+=("--upstream-model" "$FLOWDOWN_ONLINE_E2E_RECORD_MODEL_ID")
fi

mkdir -p "$E2E_SUPPORT_DIR"
mkdir -p "$BUILD_HOME" "$XDG_CACHE_HOME" "$MODULE_CACHE"

cleanup() {
    rm -f "$ENABLE_MARKER" "$RUNTIME_ENDPOINT_FILE"
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

echo "[+] starting local e2e fixture server in $SERVER_MODE mode"

python3 "$SCRIPT_DIR/online_e2e_fixture_server.py" \
    --fixture-dir "$FIXTURE_DIR" \
    --port-file "$RUNTIME_ENDPOINT_FILE" \
    --mode "$SERVER_MODE" \
    "${SERVER_ARGS[@]}" &
SERVER_PID=$!

for _ in {1..50}; do
    if [[ -s "$RUNTIME_ENDPOINT_FILE" ]]; then
        break
    fi
    sleep 0.1
done

if [[ ! -s "$RUNTIME_ENDPOINT_FILE" ]]; then
    echo "[-] local e2e fixture server did not start" >&2
    exit 1
fi

touch "$ENABLE_MARKER"
export FLOWDOWN_ONLINE_E2E_ENDPOINT="$(<"$RUNTIME_ENDPOINT_FILE")"
export FLOWDOWN_ONLINE_E2E_MODEL_ID="flowdown-local-e2e"

echo "[+] running online e2e against local fixture server"

cd "$REPO_ROOT"

DESTINATION=$(./Resources/DevKit/scripts/get_first_ios_simulator.sh)
ONLINE_TESTS=(
    "FlowDownUnitTests/OnlineCacheUsageE2ETests"
    "FlowDownUnitTests/OnlineE2ETestSupportTests"
    "FlowDownUnitTests/OnlineModelBackedE2ETests"
    "FlowDownUnitTests/OnlineReasoningStrippingE2ETests"
    "FlowDownUnitTests/OnlineReminderToolsE2ETests"
    "FlowDownUnitTests/OnlineToolAndContextE2ETests"
)
ONLY_TESTING_ARGS=()
for test in "${ONLINE_TESTS[@]}"; do
    ONLY_TESTING_ARGS+=("-only-testing:$test")
done

HOME="$BUILD_HOME" \
XDG_CACHE_HOME="$XDG_CACHE_HOME" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
XCBUILD_LABEL=test-online-e2e ./Resources/DevKit/scripts/run_xcodebuild.sh \
  -workspace FlowDown.xcworkspace \
  -scheme FlowDown \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  -parallel-testing-worker-count 1 \
  -maximum-concurrent-test-simulator-destinations 1 \
  "${ONLY_TESTING_ARGS[@]}" \
  test \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
