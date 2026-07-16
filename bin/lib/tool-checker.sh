#!/bin/bash

# Tool availability checker for secret-santa-hat-build-tools.
#
# The JS repos only need git and an authenticated GitHub CLI. JSON edits are
# done with node, which is always present in a Node project, so jq is not
# required.

if ! command -v get_platform >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/platform-utils.sh"
fi

# Check a single tool and print its version.
function check_tool() {
    local tool="$1"
    local description="$2"

    if command_exists "$tool"; then
        local version
        version=$("$tool" --version 2>/dev/null | head -1 || echo "available")
        echo "✅ $tool: $version"

        return 0
    fi

    echo "❌ $tool: not found - $description"

    return 1
}

# Check that the GitHub CLI is authenticated.
function check_gh_auth() {
    if ! command_exists "gh"; then
        echo "❌ gh: not installed - GitHub CLI (required for releases)"

        return 1
    fi

    if gh auth status >/dev/null 2>&1; then
        echo "✅ gh: authenticated"

        return 0
    fi

    echo "⚠️  gh: not authenticated (run 'gh auth login')"

    return 1
}

# Check all required tools. Pass "true" to suppress the per-tool output.
function check_all_tools() {
    local quiet_mode="${1:-false}"
    local failed=0

    if ! check_tool "git" "Version control (required)"; then
        failed=$((failed + 1))
    fi

    if ! check_tool "node" "Node.js runtime (required for JSON edits)"; then
        failed=$((failed + 1))
    fi

    if ! check_gh_auth; then
        failed=$((failed + 1))
    fi

    if [ "$quiet_mode" != "true" ]; then
        echo ""
        echo "📋 Platform: $(get_platform)"
    fi

    if [ "$failed" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Silent pass/fail check for use as a gate.
function quick_tool_check() {
    check_all_tools "true" >/dev/null 2>&1

    return $?
}
