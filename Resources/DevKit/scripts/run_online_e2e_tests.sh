#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
SUPPORT_DIR="$HOME/.testing"
DERIVED_DATA="${DERIVED_DATA:-/private/tmp/flowdown-online-e2e-deriveddata}"
BUILD_HOME="$DERIVED_DATA/home"
XDG_CACHE_HOME="$DERIVED_DATA/xdg-cache"
MODULE_CACHE="$DERIVED_DATA/ModuleCache.noindex"
TOKEN_FILE="$SUPPORT_DIR/flowdown-online-e2e.token"
ENDPOINT_FILE="$SUPPORT_DIR/flowdown-online-e2e.endpoint"
RESPONSES_ENDPOINT_FILE="$SUPPORT_DIR/flowdown-online-e2e.endpoint.responses"
MODEL_ID_FILE="$SUPPORT_DIR/flowdown-online-e2e.model-id"
HEADERS_FILE="$SUPPORT_DIR/flowdown-online-e2e.headers"
BODY_FIELDS_FILE="$SUPPORT_DIR/flowdown-online-e2e.body-fields"
E2E_SUPPORT_DIR="/tmp/flowdown-online-e2e"
ENABLE_MARKER="$E2E_SUPPORT_DIR/flowdown_e2e_enabled"
RUNTIME_TOKEN_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.token"
RUNTIME_ENDPOINT_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.endpoint"
RUNTIME_RESPONSES_ENDPOINT_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.endpoint.responses"
RUNTIME_MODEL_ID_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.model-id"
RUNTIME_HEADERS_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.headers"
RUNTIME_BODY_FIELDS_FILE="$E2E_SUPPORT_DIR/flowdown-online-e2e.body-fields"

source_user_file() {
    if [[ -f "$1" ]]; then
        set +e
        set +u
        source "$1"
        set -euo pipefail
    fi
}

source_user_file "$HOME/.zprofile"
source_user_file "$HOME/.zshrc"

mkdir -p "$SUPPORT_DIR"
mkdir -p "$E2E_SUPPORT_DIR"
mkdir -p "$BUILD_HOME" "$XDG_CACHE_HOME" "$MODULE_CACHE"

if [[ -z "${FLOWDOWN_ONLINE_E2E_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_TOKEN=$(<"$TOKEN_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_ENDPOINT:-}" && -f "$ENDPOINT_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_ENDPOINT=$(<"$ENDPOINT_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES:-}" && -f "$RESPONSES_ENDPOINT_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES=$(<"$RESPONSES_ENDPOINT_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_MODEL_ID:-}" && -f "$MODEL_ID_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_MODEL_ID=$(<"$MODEL_ID_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_HEADERS:-}" && -f "$HEADERS_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_HEADERS=$(<"$HEADERS_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_BODY_FIELDS:-}" && -f "$BODY_FIELDS_FILE" ]]; then
    FLOWDOWN_ONLINE_E2E_BODY_FIELDS=$(<"$BODY_FIELDS_FILE")
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_TOKEN:-}" ]]; then
    echo "[-] FLOWDOWN_ONLINE_E2E_TOKEN is not configured" >&2
    exit 1
fi

if [[ -z "${FLOWDOWN_ONLINE_E2E_ENDPOINT:-}" ]]; then
    echo "[-] FLOWDOWN_ONLINE_E2E_ENDPOINT is not configured" >&2
    exit 1
fi

export FLOWDOWN_ONLINE_E2E_TOKEN
export FLOWDOWN_ONLINE_E2E_ENDPOINT

if [[ -n "${FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES:-}" ]]; then
    export FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_ENABLE_RESPONSES:-}" ]]; then
    export FLOWDOWN_ONLINE_E2E_ENABLE_RESPONSES
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_MODEL_ID:-}" ]]; then
    export FLOWDOWN_ONLINE_E2E_MODEL_ID
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_HEADERS:-}" ]]; then
    export FLOWDOWN_ONLINE_E2E_HEADERS
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_BODY_FIELDS:-}" ]]; then
    export FLOWDOWN_ONLINE_E2E_BODY_FIELDS
fi

printf '%s\n' "$FLOWDOWN_ONLINE_E2E_TOKEN" > "$TOKEN_FILE"
printf '%s\n' "$FLOWDOWN_ONLINE_E2E_TOKEN" > "$RUNTIME_TOKEN_FILE"
printf '%s\n' "$FLOWDOWN_ONLINE_E2E_ENDPOINT" > "$ENDPOINT_FILE"
printf '%s\n' "$FLOWDOWN_ONLINE_E2E_ENDPOINT" > "$RUNTIME_ENDPOINT_FILE"
chmod 600 "$TOKEN_FILE" "$ENDPOINT_FILE" "$RUNTIME_TOKEN_FILE" "$RUNTIME_ENDPOINT_FILE"

if [[ -n "${FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES:-}" ]]; then
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES" > "$RESPONSES_ENDPOINT_FILE"
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES" > "$RUNTIME_RESPONSES_ENDPOINT_FILE"
    chmod 600 "$RESPONSES_ENDPOINT_FILE" "$RUNTIME_RESPONSES_ENDPOINT_FILE"
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_MODEL_ID:-}" ]]; then
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_MODEL_ID" > "$MODEL_ID_FILE"
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_MODEL_ID" > "$RUNTIME_MODEL_ID_FILE"
    chmod 600 "$MODEL_ID_FILE" "$RUNTIME_MODEL_ID_FILE"
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_HEADERS:-}" ]]; then
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_HEADERS" > "$HEADERS_FILE"
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_HEADERS" > "$RUNTIME_HEADERS_FILE"
    chmod 600 "$HEADERS_FILE" "$RUNTIME_HEADERS_FILE"
fi

if [[ -n "${FLOWDOWN_ONLINE_E2E_BODY_FIELDS:-}" ]]; then
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_BODY_FIELDS" > "$BODY_FIELDS_FILE"
    printf '%s\n' "$FLOWDOWN_ONLINE_E2E_BODY_FIELDS" > "$RUNTIME_BODY_FIELDS_FILE"
    chmod 600 "$BODY_FIELDS_FILE" "$RUNTIME_BODY_FIELDS_FILE"
fi

touch "$ENABLE_MARKER"

cleanup() {
    rm -f \
        "$ENABLE_MARKER" \
        "$RUNTIME_TOKEN_FILE" \
        "$RUNTIME_ENDPOINT_FILE" \
        "$RUNTIME_RESPONSES_ENDPOINT_FILE" \
        "$RUNTIME_MODEL_ID_FILE" \
        "$RUNTIME_HEADERS_FILE" \
        "$RUNTIME_BODY_FIELDS_FILE"
}

trap cleanup EXIT

echo "[+] running online e2e"

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
