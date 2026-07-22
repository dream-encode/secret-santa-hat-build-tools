#!/bin/bash

# The release orchestrator for secret-santa-hat-build-tools.
#
# Ported from git_create_release_quiet (gcrq). Given a JS project on the
# development or hotfix branch with a NEXT_VERSION changelog section, it bumps
# the version, finalizes and re-seeds the changelog, tags and pushes a release
# branch, publishes a GitHub release, merges into the default branch, and
# leaves the working branch ready for the next cycle.
#
# Honours DRY_RUN (set by the --dry-run flag): when true, it performs every
# read-only check and computes the target version but makes no changes.

# Clean, intentional abort. Clears the ERR trap first so a controlled failure
# does not print the "failed unexpectedly" backstop message, then exits.
function _release_abort() {
    trap - ERR 2>/dev/null || true

    exit 1
}

# Run the project's `preflight` script (tests/lint/build) with its output
# captured: a one-line pass on success, the full output on failure. This
# replaces the yarn/npm `prerelease` lifecycle hook, whose verbose output ran
# in a separate process before ssh-release and so could not be quieted here.
# Returns 0 when there is no preflight script or it passes; 1 when it fails.
function run_preflight() {
    local pm
    pm=$(get_package_manager_for_project)

    # Nothing to do when the project defines no preflight script.
    if ! node -e "const s=(require('./package.json').scripts)||{}; process.exit(s.preflight?0:1)" 2>/dev/null; then
        return 0
    fi

    printf "  Running pre-release checks..."

    local output status
    output=$("$pm" run preflight 2>&1)
    status=$?

    if [ "$status" -eq 0 ]; then
        printf " ✅\n"

        return 0
    fi

    printf " ❌\n\n"
    echo "$output"
    echo ""
    echo "❌ Pre-release checks failed. Aborting release."

    return 1
}

function ssh_create_release() {
    local version_bump="$1"

    local PACKAGE_MANAGER CURRENT_VERSION CURRENT_BRANCH DEFAULT_BRANCH
    PACKAGE_MANAGER=$(get_package_manager_for_project)
    CURRENT_VERSION=$(get_package_json_version)
    CURRENT_BRANCH=$(get_current_branch)
    DEFAULT_BRANCH=$(get_default_branch)

    # --- Guards -------------------------------------------------------------
    if ! is_git_repo; then
        echo "❌ Error: not inside a git repository."

        _release_abort
    fi

    if [ ! -f "package.json" ]; then
        echo "❌ Error: no package.json found in $(pwd)."

        _release_abort
    fi

    if [ "$CURRENT_BRANCH" != "development" ] && [ "$CURRENT_BRANCH" != "hotfix" ]; then
        echo "❌ Error: releases can only be created from 'development' or 'hotfix'."
        echo "   Current branch: $CURRENT_BRANCH"

        _release_abort
    fi

    if ! changelog_check_next_version; then
        echo "❌ Error: the top CHANGELOG.md entry is not '## [NEXT_VERSION] - [UNRELEASED]'."
        echo "   Update CHANGELOG.md before releasing."

        _release_abort
    fi

    # --- Pre-release checks ------------------------------------------------
    # Run the project's preflight script (tests/lint/build) with output captured
    # so the release stays quiet. Runs on a dry run too - a dry run should
    # exercise the same checks a real release would; only the git operations are
    # skipped.
    run_preflight || _release_abort

    # --- Keep the build tools current --------------------------------------
    # Pull the latest @secret-santa-hat/build-tools before releasing; a real
    # update records a TSK changelog entry and is committed + pushed on its own.
    # This run continues on the already-loaded version - the upgrade applies from
    # the next release. Never let a self-update issue abort the release.
    if [ "${DRY_RUN:-false}" = "true" ]; then
        node "$SCRIPT_DIR/ssh-update.js" --dry-run 2>/dev/null || true
    else
        node "$SCRIPT_DIR/ssh-update.js" || true
    fi

    # --- Determine the target version --------------------------------------
    local NEW_VERSION=""
    local do_bump="true"

    if [ -n "$version_bump" ]; then
        NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$version_bump")
    else
        echo ""
        printf "  🔢 Version selection required (current: %s)\n" "$CURRENT_VERSION"

        local options=(
            "patch - Bug fixes (${CURRENT_VERSION} -> $(calculate_new_version "$CURRENT_VERSION" "patch"))"
            "minor - New features (${CURRENT_VERSION} -> $(calculate_new_version "$CURRENT_VERSION" "minor"))"
            "major - Breaking changes (${CURRENT_VERSION} -> $(calculate_new_version "$CURRENT_VERSION" "major"))"
            "hotfix - Critical fixes (${CURRENT_VERSION} -> $(calculate_new_version "$CURRENT_VERSION" "hotfix"))"
            "custom - Enter a custom version"
            "stay - Stay at current version (${CURRENT_VERSION})"
        )

        local selected
        selected=$(interactive_menu_select "Choose the version for this release:" "${options[@]}")

        if [ -z "$selected" ]; then
            echo "❌ Version selection cancelled. Aborting release."

            _release_abort
        fi

        local action
        action=$(echo "$selected" | cut -d' ' -f1)
        printf "  ✅ Selected: %s\n" "$selected"

        case "$action" in
            stay)
                do_bump="false"
                NEW_VERSION="$CURRENT_VERSION"
                ;;
            custom)
                read -r -e -p "Enter custom version: " -i "$CURRENT_VERSION" NEW_VERSION
                if [ -z "$NEW_VERSION" ]; then
                    echo "❌ No version supplied. Aborting release."

                    _release_abort
                fi
                ;;
            *)
                NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$action")
                ;;
        esac
    fi

    # --- Dry run: report the plan and stop ---------------------------------
    if [ "${DRY_RUN:-false}" = "true" ]; then
        echo ""
        echo "🧪 Dry run - no changes will be made."
        echo "    - Package manager:  $PACKAGE_MANAGER"
        echo "    - Current branch:   $CURRENT_BRANCH"
        echo "    - Default branch:   $DEFAULT_BRANCH"
        echo "    - Current version:  $CURRENT_VERSION"

        if [ "$do_bump" = "true" ]; then
            echo "    - Target version:   $NEW_VERSION"
        else
            echo "    - Target version:   $CURRENT_VERSION (staying)"
        fi

        echo ""
        echo "  Would then: bump versions, replace [NEXT_VERSION] placeholders, commit,"
        echo "  finalize the changelog, push, create release/$NEW_VERSION, tag v$NEW_VERSION,"
        echo "  publish a GitHub release, merge into $DEFAULT_BRANCH, and re-seed the changelog."
        echo ""
        echo "  ✅ Dry run complete."

        return 0
    fi

    # --- Apply the version bump --------------------------------------------
    if [ "$do_bump" = "true" ]; then
        set_json_version "package.json" "$NEW_VERSION"
        echo "    - Updated package.json."

        if [ -f "public/manifest.json" ]; then
            set_json_version "public/manifest.json" "$NEW_VERSION"
            echo "    - Updated public/manifest.json."
        fi

        # Bump the service worker APP_VERSION in place, like package.json.
        if [ -f "public/sw.js" ]; then
            sed_inplace "s/const APP_VERSION *= *'[^']*'/const APP_VERSION = '$NEW_VERSION'/g" public/sw.js
            echo "    - Updated public/sw.js APP_VERSION."
        fi

        replace_next_version_placeholders "$NEW_VERSION"

        git add . >/dev/null 2>&1
        git commit -m "Version $NEW_VERSION bump." >/dev/null 2>&1
        echo "    - Committed version bump."
    fi

    # Refresh version in case it changed.
    CURRENT_VERSION=$(get_package_json_version)

    # --- Finalize the changelog for this version ---------------------------
    changelog_update_current_version "$CURRENT_VERSION"
    echo "    - Finalized changelog for v$CURRENT_VERSION."

    # --- Push, branch, tag -------------------------------------------------
    git push -q >/dev/null 2>&1

    git checkout -b "release/$CURRENT_VERSION" >/dev/null 2>&1
    git push -q --set-upstream origin "release/$CURRENT_VERSION" >/dev/null 2>&1
    echo "    - Release branch created."

    git tag -a "v$CURRENT_VERSION" -m "Version $CURRENT_VERSION" >/dev/null 2>&1
    git push -q -u origin "v$CURRENT_VERSION" >/dev/null 2>&1
    echo "    - Tagged v$CURRENT_VERSION."

    # --- GitHub release ----------------------------------------------------
    if ! github_create_release "$CURRENT_VERSION"; then
        echo "❌ Error: GitHub release creation failed. Aborting." >&2

        _release_abort
    fi

    if ! github_release_add_compare_link "$CURRENT_VERSION"; then
        echo "⚠️  Warning: failed to add compare link to the release." >&2
    fi

    echo "    - GitHub release created."

    # --- Merge into the default branch -------------------------------------
    git checkout "$DEFAULT_BRANCH" >/dev/null 2>&1

    # Sync the default branch with its remote before merging the release into
    # it. Commits can land on the default branch directly on the remote - most
    # often Dependabot pull requests merged from the GitHub UI - which leaves the
    # local branch stale. Merging the release onto a stale base and pushing is
    # then rejected as a non-fast-forward; because the tag and GitHub release are
    # already published above, the release would abort half-finished and strand
    # the working branch on the default branch. Fast-forward to the remote first
    # so the later push is clean, and if any step fails, stop with a clear,
    # actionable message rather than a silent, half-applied release.
    git fetch -q origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true

    if git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
        if ! git merge --ff-only "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
            echo "" >&2
            echo "❌ Error: local '$DEFAULT_BRANCH' cannot be fast-forwarded to 'origin/$DEFAULT_BRANCH'." >&2
            echo "   It has commits the remote does not - a previous release may have failed to push." >&2
            echo "   release/$CURRENT_VERSION, tag v$CURRENT_VERSION, and the GitHub release were created," >&2
            echo "   but the merge into '$DEFAULT_BRANCH' was not. Reconcile '$DEFAULT_BRANCH' with the" >&2
            echo "   remote, merge 'release/$CURRENT_VERSION' into it, push, then re-seed the changelog." >&2

            _release_abort
        fi
    fi

    if ! git merge "release/$CURRENT_VERSION" --no-ff -m "Merge release/$CURRENT_VERSION into $DEFAULT_BRANCH" >/dev/null 2>&1; then
        echo "" >&2
        echo "❌ Error: merging 'release/$CURRENT_VERSION' into '$DEFAULT_BRANCH' hit conflicts." >&2
        echo "   Commits pulled from the remote (for example Dependabot bumps) touch the same files" >&2
        echo "   as this release. Resolve the conflicts, complete the merge, and push '$DEFAULT_BRANCH'." >&2

        _release_abort
    fi

    local push_output
    if ! push_output=$(git push origin "$DEFAULT_BRANCH" 2>&1); then
        echo "" >&2
        echo "❌ Error: pushing '$DEFAULT_BRANCH' to origin failed." >&2
        printf '   %s\n' "$push_output" >&2
        echo "   The merge is committed locally; resolve the problem and push '$DEFAULT_BRANCH' manually." >&2

        _release_abort
    fi

    echo "    - Merged release/$CURRENT_VERSION into $DEFAULT_BRANCH."

    # --- Re-seed for the next cycle ----------------------------------------
    # The changelog template is left uncommitted and carried back to the working
    # branch by the checkout below, matching the gcrq end state. The service
    # worker APP_VERSION is bumped in place at release time (above), so there is
    # no [NEXT_VERSION] template to reset here.
    changelog_add_next_version_template --quiet

    git checkout "$CURRENT_BRANCH" >/dev/null 2>&1

    echo ""
    echo "  ✅ Release v$CURRENT_VERSION created."
}
