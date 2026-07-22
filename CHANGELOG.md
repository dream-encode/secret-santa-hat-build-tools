# Changelog

## [0.2.6] - 2026-07-22
* BUG: Release - Sync the default branch with its remote before merging a release into it. Commits that land on the default branch directly on the remote - most often Dependabot pull requests merged from the GitHub UI - left the local branch stale, so the release merged onto an out-of-date base and the push was rejected as a non-fast-forward. Because the tag and GitHub release were already created, the release aborted half-finished and stranded the working branch on the default branch. The default branch is now fast-forwarded to its remote first, and a failed sync, merge, or push stops with a clear reason instead of ending silently.

## [0.2.5] - 2026-07-21
* TSK: Metadata - Point the package `repository`, `bugs` and `homepage` URLs at the `secret-santa-hat` GitHub org after the repository transfer.

## [0.2.4] - 2026-07-16
* BUG: Release - Don't display the tag URL in stdout.

## [0.2.3] - 2026-07-16
* BUG: Run the `preflight` checks on `--dry-run` too. A dry run should exercise the same pre-release checks a real release does; only the git operations are skipped. 0.2.2 wrongly skipped preflight on a dry run.

## [0.2.2] - 2026-07-16
* FEA: Run pre-release checks from `ssh-release`. When the project defines a `preflight` script, `ssh-release` runs it with output captured - one line on success, the full output only on failure - so a normal release stays quiet. Name it `preflight` rather than the yarn/npm `prerelease` hook, which runs verbosely in a separate process before `ssh-release` and cannot be quieted. Skipped on `--dry-run`.

## [0.2.1] - 2026-07-16
* TWK: Bump the service worker `APP_VERSION` in place at release time (like `package.json`) instead of swapping it to and from a `[NEXT_VERSION]` template, so `public/sw.js` always holds the real version. Removes the post-release reset.

## [0.2.0] - 2026-07-16
* FEA: Self-update the build tools at the start of a release - when a newer `@secret-santa-hat/build-tools` is published, `ssh-release` upgrades it, records a `TSK: Updated @secret-santa-hat/build-tools to vX` changelog entry, and commits and pushes it (so every release runs on the latest tooling). Also available standalone as `ssh-update`; opt out with `SSH_RELEASE_NO_SELF_UPDATE=1`.

## [0.1.2] - 2026-07-16
* BUG: Release - Exclude `README.md` from the `[NEXT_VERSION]` placeholder replacement, so documentation that shows the literal `[NEXT_VERSION]` is no longer rewritten to the version number at release time.
* TSK: Publish releases from CI via GitHub Actions with npm OIDC trusted publishing, so releases no longer need a local npm token. `npmcr` detects the `publish-npm.yml` workflow and skips the manual publish.

## [0.1.1] - 2026-07-16
* TSK: Publish under the `@secret-santa-hat` npm organization as `@secret-santa-hat/build-tools`, moving it out of `@dream-encode`.

## [0.1.0] - 2026-07-16
* FEA: Initial release. Ships the `ssh-release` command, a JavaScript-tailored port of the `gcrq` (`git_create_release_quiet`) bash flow: branch and changelog guards, version bump across `package.json` and `public/manifest.json`, `[NEXT_VERSION]` placeholder replacement, changelog finalize and re-seed, release branch and tag, GitHub release with a compare link, merge to the default branch, and a service-worker version reset. Includes a postinstall that offers to wire a `release` script into the consuming project.
