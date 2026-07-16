#!/bin/bash

# Cross-platform helpers for secret-santa-hat-build-tools.

# Detect the current platform.
function get_platform() {
    case "$OSTYPE" in
        msys*|cygwin*|mingw*)
            echo "windows"
            ;;
        darwin*)
            echo "macos"
            ;;
        linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# File existence check.
function file_exists() {
    [ -f "$1" ]
}

# Command existence check.
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cross-platform sed in-place editing.
function sed_inplace() {
    local pattern="$1"
    local file="$2"

    if [[ "$(get_platform)" == "macos" ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}
