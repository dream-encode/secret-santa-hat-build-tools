# Changelog

## [NEXT_VERSION] - [UNRELEASED]
* FEA: Initial release. Ships the `ssh-release` command, a JavaScript-tailored port of the `gcrq` (`git_create_release_quiet`) bash flow: branch and changelog guards, version bump across `package.json` and `public/manifest.json`, `[NEXT_VERSION]` placeholder replacement, changelog finalize and re-seed, release branch and tag, GitHub release with a compare link, merge to the default branch, and a service-worker version reset. Includes a postinstall that offers to wire a `release` script into the consuming project.
