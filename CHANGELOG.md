# Changelog

## [NEXT_VERSION] - [UNRELEASED]
* BUG: Release - Exclude `README.md` from the `[NEXT_VERSION]` placeholder replacement, so documentation that shows the literal `[NEXT_VERSION]` is no longer rewritten to the version number at release time.
* TSK: Publish releases from CI via GitHub Actions with npm OIDC trusted publishing, so releases no longer need a local npm token. `npmcr` detects the `publish-npm.yml` workflow and skips the manual publish.

## [0.1.1] - 2026-07-16
* TSK: Publish under the `@secret-santa-hat` npm organization as `@secret-santa-hat/build-tools`, moving it out of `@dream-encode`.

## [0.1.0] - 2026-07-16
* FEA: Initial release. Ships the `ssh-release` command, a JavaScript-tailored port of the `gcrq` (`git_create_release_quiet`) bash flow: branch and changelog guards, version bump across `package.json` and `public/manifest.json`, `[NEXT_VERSION]` placeholder replacement, changelog finalize and re-seed, release branch and tag, GitHub release with a compare link, merge to the default branch, and a service-worker version reset. Includes a postinstall that offers to wire a `release` script into the consuming project.
