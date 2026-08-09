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
# Usage: strip_mlx_cuda_plugin.sh [--restore] [SourcePackages-dir ...]
# Without directories, acts on every resolved mlx-swift checkout it can find.
#
# --restore puts the pristine manifest back. Always resolve against the
# pristine manifest: the patched one drops swift-argument-parser from the
# dependency graph, so resolving on top of it records a Package.resolved that
# does not describe the real graph. See required-package-pins.json.

set -euo pipefail

mode=strip
typeset -a candidates
for argument in "$@"; do
  case "$argument" in
    --restore) mode=restore ;;
    --strip) mode=strip ;;
    -*)
      echo "[strip-mlx-cuda] unknown option: $argument" >&2
      exit 2
      ;;
    *) candidates+=("$argument") ;;
  esac
done

if (( ${#candidates} == 0 )); then
  for variable in CI_DERIVED_DATA_PATH DERIVED_DATA; do
    derived="${(P)variable:-}"
    [[ -n "$derived" ]] && candidates+=("${derived}/SourcePackages")
  done
  candidates+=(/private/tmp/flowdown-deriveddata/SourcePackages)
  candidates+=("$HOME"/Library/Developer/Xcode/DerivedData/FlowDown-*/SourcePackages(N))
  candidates=("${(@u)candidates}")
fi

found=0
for dir in "${candidates[@]}"; do
  manifest="${dir}/checkouts/mlx-swift/Package.swift"
  [[ -f "$manifest" ]] || continue
  found=1
  # SwiftPM write-protects checkouts.
  chmod u+w "$manifest"

  if [[ "$mode" == restore ]]; then
    if git -C "${dir}/checkouts/mlx-swift" checkout -- Package.swift 2>/dev/null; then
      echo "[strip-mlx-cuda] restored pristine manifest: $manifest"
    else
      echo "[strip-mlx-cuda] could not restore $manifest" >&2
      exit 1
    fi
    continue
  fi

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
  if [[ "$mode" == restore ]]; then
    echo "[strip-mlx-cuda] no resolved mlx-swift checkout to restore; nothing to do"
    exit 0
  fi
  echo "[strip-mlx-cuda] no resolved mlx-swift checkout found; resolve packages first" >&2
  exit 1
fi
