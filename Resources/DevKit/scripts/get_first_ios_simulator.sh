#!/bin/zsh

set -euo pipefail

# Discover the first iOS Simulator destination that is genuinely usable with
# the currently selected Xcode.
#
# Key insight: `simctl list` marks a runtime as isAvailable when its files
# are on disk, but Xcode N.x may still refuse to use an iOS N.(x-1) runtime.
# We therefore ensure the matching iOS platform is installed first, then
# cross-validate runtimes against devices.

find_simulator() {
    xcrun simctl list --json | python3 -c "
import sys, json

data = json.load(sys.stdin)

# collect runtime identifiers that are both iOS and genuinely available
available_ios_runtimes = {
    rt['identifier']
    for rt in data.get('runtimes', [])
    if rt.get('isAvailable', False) and 'iOS' in rt.get('name', '')
}

if not available_ios_runtimes:
    sys.exit(1)

# prefer the newest runtime (highest identifier) so we match current Xcode
for runtime_id in sorted(available_ios_runtimes, reverse=True):
    devices = data.get('devices', {}).get(runtime_id, [])
    for device in devices:
        if device.get('isAvailable', False) and 'iphone' in device.get('name', '').lower():
            print(device['udid'])
            sys.exit(0)

sys.exit(1)
"
}

# ensure the iOS platform matching the current Xcode is installed
# (fast no-op when already present)
echo "[*] ensuring iOS platform is installed for current Xcode..." >&2
xcodebuild -downloadPlatform iOS 2>&1 | while IFS= read -r line; do echo "    $line" >&2; done

SIMULATOR=$(find_simulator) || {
    echo "[-] no available iPhone simulator found after platform install" >&2
    exit 1
}

echo "[+] using simulator: $SIMULATOR" >&2
echo "platform=iOS Simulator,id=$SIMULATOR"
