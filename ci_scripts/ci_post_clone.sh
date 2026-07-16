#!/bin/zsh

set -euo pipefail

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES

echo "[+] package plugin validation disabled"
