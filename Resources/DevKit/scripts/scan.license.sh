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

SCANNED_LICENSE_CONTENT="# Open Source License\n\n"

for dir in "${SCANNER_DIR[@]}"; do
    if [[ -d "$dir" ]]; then
        # spm may have duplicated LICENSE file inside their own .build directory
        for file in $(find "$dir" -name .build -prune -o -name "LICENSE*" -type f -print); do
            PACKAGE_NAME=$(get_correct_package_name $(basename $(dirname $file)))
            SCANNED_LICENSE_CONTENT="${SCANNED_LICENSE_CONTENT}\n\n## ${PACKAGE_NAME}\n\n$(cat $file)"
        done
        for file in $(find "$dir" -name .build -prune -o -name "COPYING*" -type f -print); do
            PACKAGE_NAME=$(get_correct_package_name $(basename $(dirname $file)))

            # special handling for zstd license, it was dual licensed with BSD and GPL
            # https://github.com/facebook/zstd/issues/3717
            if [[ "$PACKAGE_NAME" == "zstd" ]]; then
                continue
            fi

            SCANNED_LICENSE_CONTENT="${SCANNED_LICENSE_CONTENT}\n\n## ${PACKAGE_NAME}\n\n$(cat $file)"
        done
    fi
done

echo -e "$SCANNED_LICENSE_CONTENT" >"$PROJECT_ROOT/FlowDown/BundledResources/OpenSourceLicenses.md"

echo "[*] checking for incompatible licenses..."

INCOMPATIBLE_LICENSES_KEYWORDS=(
    "GNU General Public License"
    "GNU Lesser General Public License"
    "GNU Affero General Public License"
)

for keyword in "${INCOMPATIBLE_LICENSES_KEYWORDS[@]}"; do
    if grep -q "$keyword" "$PROJECT_ROOT/FlowDown/BundledResources/OpenSourceLicenses.md"; then
        echo "[!] found incompatible license: $keyword"
        exit 1
    fi
done

echo "[*] done"
