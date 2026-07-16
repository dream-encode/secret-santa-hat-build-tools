#!/bin/bash

# General helpers for secret-santa-hat-build-tools.
#
# JSON reads/writes go through node rather than jq: node is guaranteed present
# in a Node project and preserves the 2-space formatting these repos use.

# Detect the package manager for the current project.
function get_package_manager_for_project() {
    if [ -f yarn.lock ]; then
        echo "yarn"
    else
        echo "npm"
    fi
}

# Read a version field from a JSON file. Usage: get_json_version <file>
function get_json_version() {
    local file="$1"

    node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).version || ''))" "$file" 2>/dev/null
}

# Read the project version from package.json.
function get_package_json_version() {
    get_json_version "package.json"
}

# Write a version field to a JSON file, preserving 2-space formatting and a
# trailing newline. Usage: set_json_version <file> <version>
function set_json_version() {
    local file="$1"
    local version="$2"

    node -e "const fs=require('fs');const f=process.argv[1];const v=process.argv[2];const j=JSON.parse(fs.readFileSync(f,'utf8'));j.version=v;fs.writeFileSync(f, JSON.stringify(j,null,2)+'\n');" "$file" "$version"
}

# Calculate a new version from a bump type. Supports X.X.X and X.X.X.X.
function calculate_new_version() {
    local current_version="$1"
    local bump_type="$2"

    IFS='.' read -ra VERSION_PARTS <<< "$current_version"

    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}
    local hotfix=${VERSION_PARTS[3]:-}

    case $bump_type in
        "patch")
            patch=$((patch + 1))
            hotfix=""
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            hotfix=""
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            hotfix=""
            ;;
        "hotfix")
            if [ -z "$hotfix" ]; then
                hotfix=1
            else
                hotfix=$((hotfix + 1))
            fi
            ;;
        *)
            echo "Invalid bump type: $bump_type. Use patch, minor, major, or hotfix." >&2

            return 1
            ;;
    esac

    if [ -n "$hotfix" ]; then
        echo "$major.$minor.$patch.$hotfix"
    else
        echo "$major.$minor.$patch"
    fi
}

# Interactive menu selection with fzf/whiptail/numbered fallbacks.
function interactive_menu_select() {
    local prompt="$1"
    shift
    local options=("$@")

    if command -v fzf >/dev/null 2>&1; then
        local result
        result=$(printf '%s\n' "${options[@]}" | fzf --height=12 --layout=reverse --border --prompt="Select: " --header="$prompt")

        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "$result"

            return 0
        fi

        return 1
    fi

    if command -v whiptail >/dev/null 2>&1; then
        local menu_items=()
        local i
        for i in "${!options[@]}"; do
            menu_items+=("$((i+1))" "${options[i]}")
        done

        local choice
        choice=$(whiptail --title "Version Bump" --menu "$prompt" 18 90 8 "${menu_items[@]}" 3>&1 1>&2 2>&3)

        if [ $? -eq 0 ] && [ -n "$choice" ]; then
            echo "${options[$((choice-1))]}"

            return 0
        fi

        return 1
    fi

    echo "$prompt" >&2
    echo "" >&2

    local i
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[i]}" >&2
    done
    echo "" >&2

    while true; do
        read -r -p "Enter your choice (1-${#options[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"

            return 0
        fi

        echo "Invalid choice. Please enter a number between 1 and ${#options[@]}." >&2
    done
}

# Changelog helpers.
function changelog_exists() {
    [ -f "CHANGELOG.md" ]
}

# True when CHANGELOG.md has a NEXT_VERSION / UNRELEASED section at the top.
function changelog_check_next_version() {
    if changelog_exists && grep -q "## \[NEXT_VERSION\] - \[UNRELEASED\]" CHANGELOG.md; then
        return 0
    fi

    return 1
}

# Extract the bullet notes for a version from CHANGELOG.md, as GitHub release
# body. Supports X.X.X and X.X.X.X.
function extract_version_updates_from_changelog() {
    local RELEASE_VERSION="$1"
    local CHANGELOG_FILE="CHANGELOG.md"

    if [ ! -f "$CHANGELOG_FILE" ]; then
        return 1
    fi

    awk -v ver="$RELEASE_VERSION" '
        $0 ~ "^## \\[" ver "\\]" { print "## Changelog"; version_found=1; next }
        /^## \[/ && version_found { exit }
        version_found && /^\*/' "$CHANGELOG_FILE"
}

# Replace the NEXT_VERSION section header with the released version and date,
# then commit that changelog change.
function changelog_update_current_version() {
    local CURRENT_VERSION="${1:-$(get_package_json_version)}"

    if changelog_exists && grep -q "## \[NEXT_VERSION\]" CHANGELOG.md; then
        local CURRENT_DATE
        CURRENT_DATE=$(date +%Y-%m-%d)

        sed_inplace "s/^## \[NEXT_VERSION\] - \[UNRELEASED\]$/## [$CURRENT_VERSION] - $CURRENT_DATE/" CHANGELOG.md

        git add CHANGELOG.md >/dev/null 2>&1
        git commit -m "Update changelog for v$CURRENT_VERSION" >/dev/null 2>&1
    fi
}

# Re-seed a fresh NEXT_VERSION section above the just-released version.
function changelog_add_next_version_template() {
    local CURRENT_VERSION=""
    local QUIET_MODE="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --quiet)
                QUIET_MODE="true"
                shift
                ;;
            --version)
                CURRENT_VERSION="$2"
                shift 2
                ;;
            *)
                echo "❌ Error: unknown argument '$1' for changelog_add_next_version_template" >&2

                return 1
                ;;
        esac
    done

    if [ -z "$CURRENT_VERSION" ]; then
        CURRENT_VERSION=$(get_package_json_version)
    fi

    if changelog_exists; then
        sed_inplace "s/^## \[$CURRENT_VERSION\]/## [NEXT_VERSION] - [UNRELEASED]\n* BUG: Example fix description.\n\n## [$CURRENT_VERSION]/" CHANGELOG.md

        if [ "$QUIET_MODE" != "true" ]; then
            echo "✅ Template changelog entry added to CHANGELOG.md"
        fi
    fi
}

# Replace [NEXT_VERSION] placeholders across project files (skipping the
# changelog, shell scripts, binaries, and dependency directories).
function replace_next_version_placeholders() {
    local new_version="$1"

    if ! command -v grep >/dev/null 2>&1; then
        return 0
    fi

    local files
    files=$(grep -r -l "\[NEXT_VERSION\]" . \
        --exclude-dir=node_modules \
        --exclude-dir=vendor \
        --exclude-dir=.git \
        --exclude-dir=dist \
        --exclude-dir=build \
        --exclude="*.zip" \
        --exclude="*.tar.gz" \
        --exclude="*.jpg" \
        --exclude="*.jpeg" \
        --exclude="*.png" \
        --exclude="*.gif" \
        --exclude="*.ico" \
        --exclude="*.svg" \
        --exclude="*.webp" \
        --exclude="*.pdf" \
        --exclude="*.woff" \
        --exclude="*.woff2" \
        --exclude="*.ttf" \
        --exclude="*.eot" \
        --exclude="*.mp4" \
        --exclude="*.mp3" \
        --exclude="*.wav" \
        --exclude="*.lock" \
        --exclude="*.sh" \
        --exclude="CHANGELOG.md" \
        --exclude="README.md" \
        2>/dev/null || true)

    if [ -n "$files" ]; then
        echo "$files" | while IFS= read -r file; do
            if [ -f "$file" ]; then
                sed_inplace "s/\[NEXT_VERSION\]/$new_version/g" "$file"
            fi
        done

        echo "    - Replaced [NEXT_VERSION] with $new_version in files."
    fi
}

# Reset the service worker APP_VERSION back to the [NEXT_VERSION] template.
function update_service_worker_next_version_template() {
    if [ -f "public/sw.js" ]; then
        sed_inplace "s/const APP_VERSION *= *'[^']*'/const APP_VERSION = '[NEXT_VERSION]'/g" public/sw.js

        echo "    - Updated service worker version template."
    fi
}
