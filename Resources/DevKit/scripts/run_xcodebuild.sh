#!/bin/zsh

set -euo pipefail

# Shared wrapper for build and test entrypoints.
# It treats the log content as the source of truth so `make` stops on real
# compiler or test failures even when `xcodebuild` exits successfully.

LABEL="${XCBUILD_LABEL:-xcodebuild}"
RAW_LOG=$(mktemp -t "flowdown-${LABEL//\//_}.raw.XXXXXX.log")
LOG=$(mktemp -t "flowdown-${LABEL//\//_}.XXXXXX.log")
FILTER_RE='Metal\.xctoolchain/usr/lib/swift/maccatalyst|CoreData: error: Failed to create NSXPCConnection'
trap 'rm -f "$RAW_LOG" "$LOG"' EXIT

capture_direct() {
    if xcodebuild "$@" >"$RAW_LOG" 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

capture_with_pty() {
    if script -q "$RAW_LOG" xcodebuild "$@" >/dev/null 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

normalize_log() {
    perl -ne '
        s/\r/\n/g;
        s/\x08//g;
        s/\x04//g;
        next if m{Metal\.xctoolchain/usr/lib/swift/maccatalyst};
        next if m{CoreData: error: Failed to create NSXPCConnection};
        print;
    ' "$RAW_LOG" >"$LOG"
}

capture_direct "$@"
normalize_log

if [ "${XCBUILD_FORCE_PTY:-0}" = "1" ] || grep -F "is not a workspace file" "$LOG" >/dev/null 2>&1; then
    capture_with_pty "$@"
    normalize_log
fi

replay_log() {
    if command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify --disable-colored-output --disable-logging <"$LOG" | grep -Ev "$FILTER_RE" || true
    else
        grep -Ev "$FILTER_RE" "$LOG" || true
    fi
}

replay_log

ERR_RE='^[[:space:]]*error:|^[^[:space:]].*:[0-9]+:[0-9]+: error:|^\*\* (BUILD|TEST|ARCHIVE|CLEAN|ANALYZE) FAILED \*\*|^Testing failed:|^Failing tests:'

FOUND_ERRORS=0
if grep -En "$ERR_RE" "$LOG" >/dev/null 2>&1; then
    FOUND_ERRORS=1
fi

if [ "$XC_STATUS" -ne 0 ] || [ "$FOUND_ERRORS" -ne 0 ]; then
    echo "" >&2
    echo "[-] [$LABEL] xcodebuild failed (exit=$XC_STATUS, errors_in_log=$FOUND_ERRORS)" >&2
    if [ "$FOUND_ERRORS" -ne 0 ]; then
        echo "---- first 40 error lines from log ----" >&2
        grep -En "$ERR_RE" "$LOG" | head -40 >&2 || true
        echo "---------------------------------------" >&2
    fi
    if [ "$XC_STATUS" -ne 0 ]; then
        exit "$XC_STATUS"
    fi
    exit 1
fi
