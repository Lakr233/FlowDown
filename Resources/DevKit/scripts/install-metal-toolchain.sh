#!/bin/zsh

set -euo pipefail

echo "[+] installing metal toolchain..."
xcodebuild -downloadComponent MetalToolchain
echo "[+] metal toolchain ready"
