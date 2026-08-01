#!/bin/zsh

# Strips the CUDA build-tool plugin (encuda + CudaBuild) from the resolved
# mlx-swift checkout. mlx-swift >= 0.31.5 attaches the plugin to its Cmlx
# target, and during `xcodebuild archive` for macOS every top-level target
# linking MLX emits the plugin tool into the shared UninstalledProducts
# directory, failing with:
#   Multiple commands produce '.../UninstalledProducts/macosx/encuda'
#   Multiple commands produce '.../UninstalledProducts/macosx/ArgumentParser.o'
# The plugin only emits build commands when CUDA is enabled, so it is a no-op
# on Apple platforms and safe to remove from the manifest.
#
# Usage: strip_mlx_cuda_plugin.sh [SourcePackages-dir ...]
# Without arguments, patches every resolved mlx-swift checkout it can find.

set -euo pipefail

typeset -a candidates
if (( $# > 0 )); then
  candidates=("$@")
else
  if [[ -n "${CI_DERIVED_DATA_PATH:-}" ]]; then
    candidates+=("${CI_DERIVED_DATA_PATH}/SourcePackages")
  fi
  candidates+=("$HOME"/Library/Developer/Xcode/DerivedData/FlowDown-*/SourcePackages(N))
fi

found=0
for dir in "${candidates[@]}"; do
  manifest="${dir}/checkouts/mlx-swift/Package.swift"
  [[ -f "$manifest" ]] || continue
  found=1
  # SwiftPM write-protects checkouts.
  chmod u+w "$manifest"
  /usr/bin/env python3 - "$manifest" <<'EOF'
import re
import sys

path = sys.argv[1]
with open(path) as f:
    text = f.read()

if "encuda" not in text:
    print(f"[strip-mlx-cuda] already patched: {path}")
    sys.exit(0)

# Detach the plugin from the Cmlx target.
text = re.sub(r'[ \t]*plugins: \[\s*\.plugin\(name: "CudaBuild"\),?\s*\],\n', "", text)
# Drop the encuda tool target.
text = re.sub(r'[ \t]*\.executableTarget\(\s*name: "encuda",.*?\n[ \t]*\),\n', "", text, flags=re.S)
# Drop the CudaBuild plugin target.
text = re.sub(r'[ \t]*\.plugin\(\s*name: "CudaBuild",.*?\n[ \t]*\),\n', "", text, flags=re.S)

if "encuda" in text or "CudaBuild" in text:
    print(f"[strip-mlx-cuda] patch failed for {path}; manifest layout changed?", file=sys.stderr)
    sys.exit(1)

with open(path, "w") as f:
    f.write(text)
print(f"[strip-mlx-cuda] patched: {path}")
EOF
done

if (( ! found )); then
  echo "[strip-mlx-cuda] no resolved mlx-swift checkout found; resolve packages first" >&2
  exit 1
fi
