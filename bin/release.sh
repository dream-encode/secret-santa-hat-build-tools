#!/bin/bash

# Secret Santa Hat release script.
#
# A JavaScript-tailored port of the `git_create_release_quiet` (gcrq) bash
# function. Handles version bumping, changelog management, git tagging, GitHub
# releases, and the post-release merge/reseed cycle for the Secret Santa Hat
# JS repositories.

set -e

trap 'printf "\n❌ Release failed unexpectedly on line %s (exit code: %s).\n" "$LINENO" "$?" >&2' ERR

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export TERM="${TERM:-xterm-256color}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_PROJECT_DIR="$(pwd)"

function show_help() {
    cat << 'EOF'
NAME
    ssh-release - Secret Santa Hat release tool

SYNOPSIS
    ssh-release [OPTIONS] [VERSION_TYPE]

DESCRIPTION
    Creates a release for a Secret Santa Hat JavaScript project: bumps the
    version, finalizes the changelog, tags the release, publishes a GitHub
    release, merges into the default branch, and re-seeds the next changelog
    section. Ported from the gcrq (git_create_release_quiet) bash flow.

    Releases can only be created from the 'development' or 'hotfix' branch, and
    CHANGELOG.md must have a "## [NEXT_VERSION] - [UNRELEASED]" section at the
    top.

OPTIONS
    --check-tools      Check that git and gh (authenticated) are available
    --dry-run          Walk through the release without pushing, tagging, or
                       publishing anything (still shows the computed version)
    --help, -h         Show this help message
    --version, -v      Show version information

VERSION_TYPE
    patch              Bug fixes (1.0.0 -> 1.0.1)
    minor              New features (1.0.0 -> 1.1.0)
    major              Breaking changes (1.0.0 -> 2.0.0)
    hotfix             Critical fixes (1.0.0 -> 1.0.0.1)

    If no VERSION_TYPE is given, interactive mode prompts for the bump.

EXAMPLES
    ssh-release                 # Interactive mode
    ssh-release patch           # Patch release
    ssh-release --dry-run minor # Preview a minor release
    ssh-release --check-tools   # Verify required tools

REQUIREMENTS
    - git   Version control
    - gh    GitHub CLI, authenticated (gh auth login)
    - node  Used for package.json / manifest.json edits (always present in a
            Node project)

FILES OPERATED ON
    package.json           Version source of truth
    CHANGELOG.md           Release notes, NEXT_VERSION section
    public/manifest.json   Version, if present
    public/sw.js           APP_VERSION reset to [NEXT_VERSION], if present
    *                      Any file containing the [NEXT_VERSION] placeholder
EOF
}

# Parse arguments.
DRY_RUN=false
CHECK_TOOLS=false
VERSION_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "ssh-release (secret-santa-hat-build-tools)"
            exit 0
            ;;
        --check-tools)
            CHECK_TOOLS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --quiet)
            # Accepted for gcrq parity; the flow is quiet by default.
            shift
            ;;
        patch|minor|major|hotfix)
            if [ -n "$VERSION_TYPE" ]; then
                echo "❌ Error: multiple version types specified."
                exit 1
            fi
            VERSION_TYPE="$1"
            shift
            ;;
        -*)
            echo "❌ Error: unknown option '$1'. See 'ssh-release --help'."
            exit 1
            ;;
        *)
            echo "❌ Error: unexpected argument '$1'. See 'ssh-release --help'."
            exit 1
            ;;
    esac
done

# Source configuration if present.
if [ -f "$SCRIPT_DIR/config/release.conf" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config/release.conf"
fi

# Source helper libraries.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/platform-utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tool-checker.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/general-functions.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/git-functions.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/release-functions.sh"

# Operate in the user's project directory.
cd "$USER_PROJECT_DIR"

if [ "$CHECK_TOOLS" = true ]; then
    echo "🔧 Checking required tools..."
    echo ""

    if check_all_tools; then
        echo ""
        echo "✅ All required tools are available. Ready to run ssh-release."
        exit 0
    else
        echo ""
        echo "❌ Some required tools are missing or not configured."
        echo "   • git: https://git-scm.com/downloads"
        echo "   • gh:  https://cli.github.com/  (then run: gh auth login)"
        exit 1
    fi
fi

# Normal release workflow: verify tools first.
if ! quick_tool_check; then
    echo "🔧 Checking required tools..."
    echo ""
    check_all_tools || true
    echo ""
    echo "❌ Missing required tools. Install them before running ssh-release."
    echo "   Run 'ssh-release --check-tools' for details."
    exit 1
fi

if [ -n "$VERSION_TYPE" ]; then
    ssh_create_release "$VERSION_TYPE"
else
    ssh_create_release
fi
