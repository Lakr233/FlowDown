#!/bin/zsh

cd "$(dirname "$0")"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

if [[ -d .git ]] && [[ -d FlowDown.xcworkspace ]]; then
    echo "[*] found project root: $(pwd)"
else
    echo "[!] could not find project root"
    exit 1
fi

PROJECT_ROOT=$(pwd)
PACKAGE_CLONE_ROOT="${PROJECT_ROOT}/.build/license.scanner/dependencies"

function with_retry {
    local retries=3
    local count=0
    while [[ $count -lt $retries ]]; do
        "$@"
        if [[ $? -eq 0 ]]; then
            return 0
        fi
        count=$((count + 1))
    done
    return 1
}

if [[ -n $(git status --porcelain) ]]; then
    if [[ "${ALLOW_DIRTY:-0}" == "1" ]]; then
        echo "[*] git is not clean; continuing because ALLOW_DIRTY=1"
    else
        echo "[!] git is not clean"
        exit 1
    fi
fi

echo "[*] resolving packages..."

# Checkouts left over from packages that are no longer pinned would leak into
# the scan; drop them so only the current graph is checked out again from the
# cached repositories.
rm -rf "$PACKAGE_CLONE_ROOT/checkouts" "$PACKAGE_CLONE_ROOT/workspace-state.json"

with_retry xcodebuild -resolvePackageDependencies \
    -clonedSourcePackagesDirPath "$PACKAGE_CLONE_ROOT" \
    -workspace *.xcworkspace \
    -scheme FlowDown |
    xcbeautify
(( ${pipestatus[1]} == 0 )) || { echo "[-] package resolution failed"; exit 1; }
[[ -d "$PACKAGE_CLONE_ROOT/checkouts" ]] || { echo "[-] no package checkouts found"; exit 1; }

echo "[*] scanning licenses..."

SCANNER_DIR=(
    "$PROJECT_ROOT/Frameworks"
    "$PROJECT_ROOT/Resources/AdditionalLicenses"
    "$PACKAGE_CLONE_ROOT/checkouts"
)

# Build package name mapping from Package.resolved
declare -A PACKAGE_NAME_MAP
PACKAGE_RESOLVED="${PROJECT_ROOT}/FlowDown.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# Manual corrections for packages where GitHub URL is lowercase but actual name has different casing
declare -A MANUAL_CORRECTIONS=(
    ["listviewkit"]="ListViewKit"
)

if [[ -f "$PACKAGE_RESOLVED" ]]; then
    echo "[*] reading package names from Package.resolved..."
    # Extract identity (lowercase) and location (with correct case) pairs
    while IFS= read -r line; do
        if [[ $line =~ \"identity\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            identity="${match[1]}"
            # Check manual corrections first
            if [[ -n "${MANUAL_CORRECTIONS[$identity]}" ]]; then
                PACKAGE_NAME_MAP[$identity]="${MANUAL_CORRECTIONS[$identity]}"
            else
                # Read next few lines to find location
                read -r location_line
                if [[ $location_line =~ \"location\"[[:space:]]*:[[:space:]]*\"[^/]+/([^/\"]+)\" ]]; then
                    repo_name="${match[1]}"
                    # Remove .git suffix if present
                    repo_name="${repo_name%.git}"
                    PACKAGE_NAME_MAP[$identity]="$repo_name"
                fi
            fi
        fi
    done < <(grep -A 1 '"identity"' "$PACKAGE_RESOLVED")
fi

function get_correct_package_name {
    local dir_name=$1
    local lowercase_name=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')
    
    # Try to find in the map
    if [[ -n "${PACKAGE_NAME_MAP[$lowercase_name]}" ]]; then
        echo "${PACKAGE_NAME_MAP[$lowercase_name]}"
    else
        # Fallback to original name
        echo "$dir_name"
    fi
}

LICENSE_OUTPUT="$PROJECT_ROOT/FlowDown/BundledResources/OpenSourceLicenses.md"

# find returns files in directory order, which differs between machines;
# sort with a fixed collation so the output only changes when a license does.
function license_files {
    # spm may have duplicated LICENSE file inside their own .build directory
    find "$1" -name .build -prune -o -name "$2" -type f -print0 | LC_ALL=C sort -z
}

{
    printf '# Open Source License\n\n'
    for dir in "${SCANNER_DIR[@]}"; do
        [[ -d "$dir" ]] || continue
        for file in ${(0)"$(license_files "$dir" "LICENSE*")"}; do
            PACKAGE_NAME=$(get_correct_package_name "$(basename "$(dirname "$file")")")
            printf '\n\n## %s\n\n%s' "$PACKAGE_NAME" "$(<"$file")"
        done
        for file in ${(0)"$(license_files "$dir" "COPYING*")"}; do
            PACKAGE_NAME=$(get_correct_package_name "$(basename "$(dirname "$file")")")

            # special handling for zstd license, it was dual licensed with BSD and GPL
            # https://github.com/facebook/zstd/issues/3717
            if [[ "$PACKAGE_NAME" == "zstd" ]]; then
                continue
            fi

            printf '\n\n## %s\n\n%s' "$PACKAGE_NAME" "$(<"$file")"
        done
    done
    printf '\n'
} >"$LICENSE_OUTPUT"

echo "[*] checking for incompatible licenses..."

INCOMPATIBLE_LICENSES_KEYWORDS=(
    "GNU General Public License"
    "GNU Lesser General Public License"
    "GNU Affero General Public License"
)

for keyword in "${INCOMPATIBLE_LICENSES_KEYWORDS[@]}"; do
    if grep -q "$keyword" "$LICENSE_OUTPUT"; then
        echo "[!] found incompatible license: $keyword"
        exit 1
    fi
done

echo "[*] done"
