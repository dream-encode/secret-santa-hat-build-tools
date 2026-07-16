# Secret Santa Hat Build Tools

Release tooling for the Secret Santa Hat JavaScript repositories. Ships the
`ssh-release` command, a JS-tailored port of the `gcrq`
(`git_create_release_quiet`) bash flow, so every repo releases the same way
without depending on a personal shell profile.

## What it does

Running `ssh-release` from a repo on the `development` (or `hotfix`) branch:

1. Verifies the branch and that `CHANGELOG.md` has a
   `## [NEXT_VERSION] - [UNRELEASED]` section at the top.
2. Bumps the version (interactive menu, or `patch`/`minor`/`major`/`hotfix`):
   - `package.json`
   - `public/manifest.json` (if present)
   - any file containing the `[NEXT_VERSION]` placeholder
3. Commits the bump, then rewrites the changelog `NEXT_VERSION` header to the
   new version and date and commits that.
4. Pushes, creates a `release/<version>` branch, and tags `v<version>`.
5. Creates a GitHub release from the changelog notes and appends a
   **Full Changelog** compare link.
6. Merges the release branch into the default branch (`main`/`master`) and
   pushes it.
7. Re-seeds a fresh `NEXT_VERSION` changelog section and resets
   `public/sw.js` `APP_VERSION` back to `[NEXT_VERSION]`, then returns to the
   working branch.

JSON edits are done with `node` (always present in a Node project), so `jq` is
not required.

## Requirements

- **git**
- **gh** (GitHub CLI), authenticated: `gh auth login`
- **bash** — Git Bash on Windows; already present on macOS/Linux
- **node** — provided by the project itself

Check everything with:

```bash
ssh-release --check-tools
```

## Install

```bash
# yarn (classic)
yarn add --dev @secret-santa-hat/build-tools

# npm
npm install --save-dev @secret-santa-hat/build-tools
```

After install, wire the `release` script into the project:

```bash
npx @secret-santa-hat/build-tools setup          # interactive
npx @secret-santa-hat/build-tools setup --force  # no prompts
```

This sets `"release": "ssh-release"`. Any existing custom release script is
backed up as `release-backup`.

## Pre-release checks (`preflight`)

Keep each repo's pre-flight checks (tests, lint, build, ...) in a `preflight`
script. `ssh-release` runs it itself, **with the output captured** — a single
line on success, the full output only when it fails. Name it `preflight`, not
`prerelease`: a `prerelease` script is a yarn/npm lifecycle hook that runs
verbosely in a separate process *before* `ssh-release`, so its output cannot be
quieted.

```jsonc
{
  "scripts": {
    // repo-specific checks, run quietly by ssh-release before the release
    "preflight": "yarn maintenance && yarn test:unit",
    // the shared release flow
    "release": "ssh-release"
  }
}
```

```bash
yarn release          # runs preflight (quiet), then the interactive release
yarn release --dry-run
```

## Usage

```bash
ssh-release                 # interactive version selection
ssh-release patch           # 1.0.0 -> 1.0.1
ssh-release minor           # 1.0.0 -> 1.1.0
ssh-release major           # 1.0.0 -> 2.0.0
ssh-release hotfix          # 1.0.0 -> 1.0.0.1
ssh-release --dry-run minor # preview without making changes
ssh-release --check-tools   # verify git + gh
ssh-release --help
```

Because `release` passes arguments through, `yarn release patch` and
`yarn release --dry-run` work too.

## Configuration

Optional. Copy `bin/config/release.conf.example` to `bin/config/release.conf`
inside the installed package to override defaults:

- `SSH_RELEASE_MAIN_BRANCH` — the branch releases merge into (auto-detected as
  `main`, then `master`, when unset).

## Notes

- Releases are allowed only from `development` or `hotfix`.
- The version bump commit runs `git add .`, so the working tree should hold
  only what you intend to ship.
- The re-seeded `NEXT_VERSION` changelog section and the `sw.js` reset are left
  uncommitted on the working branch, ready for the next cycle.
