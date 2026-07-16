#!/usr/bin/env node

/*
 * ssh-update - keep @secret-santa-hat/build-tools current.
 *
 * Checks the installed build-tools version against the latest published on npm.
 * If the project is behind, it upgrades the dependency, records a
 * `* TSK: Updated @secret-santa-hat/build-tools to vX.Y.Z.` entry under the
 * CHANGELOG NEXT_VERSION section (refreshing any prior such line so it never
 * duplicates, or replacing the example stub), then commits and pushes.
 *
 * ssh-release runs this automatically at the start of a release; it is also
 * available standalone as `ssh-update` (wpubt-style).
 *
 * Flags:
 *   --dry-run   Report whether an update is available; make no changes.
 *   --quiet     Only speak when something actually happens.
 *
 * Opt out entirely with SSH_RELEASE_NO_SELF_UPDATE=1.
 */

const { spawnSync } = require( 'child_process' )
const fs   = require( 'fs' )
const path = require( 'path' )

const PACKAGE_NAME = '@secret-santa-hat/build-tools'

const args   = process.argv.slice( 2 )
const dryRun = args.includes( '--dry-run' )
const quiet  = args.includes( '--quiet' )

function log( message ) {
	console.log( message )
}

function info( message ) {
	if ( ! quiet ) {
		log( message )
	}
}

// Run a shell command; returns { status, stdout, stderr }.
function sh( command, opts = {} ) {
	return spawnSync( command, { shell: true, encoding: 'utf8', cwd: process.cwd(), ...opts } )
}

function readJson( file ) {
	return JSON.parse( fs.readFileSync( file, 'utf8' ) )
}

// Split a dotted version into numeric parts (supports X.Y.Z and X.Y.Z.W).
function parseVersion( version ) {
	return String( version ).replace( /^[\^~]/, '' ).split( '.' ).map( ( n ) => parseInt( n, 10 ) || 0 )
}

// True when version a is strictly greater than version b.
function isNewer( a, b ) {
	const pa = parseVersion( a )
	const pb = parseVersion( b )
	const len = Math.max( pa.length, pb.length )

	for ( let i = 0; i < len; i++ ) {
		const da = pa[ i ] || 0
		const db = pb[ i ] || 0

		if ( da > db ) {
			return true
		}

		if ( da < db ) {
			return false
		}
	}

	return false
}

// Add or refresh the build-tools TSK entry under the CHANGELOG NEXT_VERSION
// section. Returns true when the changelog was changed.
function updateChangelog( newVersion ) {
	const clPath = path.join( process.cwd(), 'CHANGELOG.md' )

	if ( ! fs.existsSync( clPath ) ) {
		return false
	}

	const entry = `* TSK: Updated ${ PACKAGE_NAME } to v${ newVersion }.`
	const raw   = fs.readFileSync( clPath, 'utf8' )
	const lines = raw.split( '\n' )

	const startIdx = lines.findIndex( ( l ) => /^## \[NEXT_VERSION\] - \[UNRELEASED\]/.test( l ) )

	if ( startIdx === -1 ) {
		return false
	}

	// End of the section: the next "## [" header, or end of file.
	let endIdx = lines.length
	for ( let i = startIdx + 1; i < lines.length; i++ ) {
		if ( /^## \[/.test( lines[ i ] ) ) {
			endIdx = i
			break
		}
	}

	let existingIdx  = -1
	let exampleIdx   = -1
	let lastEntryIdx = -1
	let hasReal      = false

	for ( let i = startIdx + 1; i < endIdx; i++ ) {
		if ( ! /^\* /.test( lines[ i ] ) ) {
			continue
		}

		lastEntryIdx = i

		if ( lines[ i ].includes( `Updated ${ PACKAGE_NAME } to v` ) ) {
			existingIdx = i
		} else if ( /^\* BUG: Example fix description\.$/.test( lines[ i ] ) ) {
			exampleIdx = i
		} else {
			hasReal = true
		}
	}

	if ( existingIdx !== -1 ) {
		if ( lines[ existingIdx ] === entry ) {
			return false
		}

		lines[ existingIdx ] = entry
	} else if ( exampleIdx !== -1 && ! hasReal ) {
		lines[ exampleIdx ] = entry
	} else if ( lastEntryIdx !== -1 ) {
		lines.splice( lastEntryIdx + 1, 0, entry )
	} else {
		lines.splice( startIdx + 1, 0, entry )
	}

	fs.writeFileSync( clPath, lines.join( '\n' ) )

	return true
}

function main() {
	if ( process.env.SSH_RELEASE_NO_SELF_UPDATE === '1' ) {
		return 0
	}

	const pkgPath = path.join( process.cwd(), 'package.json' )

	if ( ! fs.existsSync( pkgPath ) ) {
		return 0
	}

	const pkg     = readJson( pkgPath )
	const isDev   = !! ( pkg.devDependencies && pkg.devDependencies[ PACKAGE_NAME ] )
	const isProd  = !! ( pkg.dependencies && pkg.dependencies[ PACKAGE_NAME ] )

	if ( ! isDev && ! isProd ) {
		// This project does not consume the build tools; nothing to do.
		return 0
	}

	const installedPkgPath = path.join( process.cwd(), 'node_modules', PACKAGE_NAME, 'package.json' )

	if ( ! fs.existsSync( installedPkgPath ) ) {
		return 0
	}

	const installed = readJson( installedPkgPath ).version

	const view = sh( `npm view ${ PACKAGE_NAME } version` )

	if ( view.status !== 0 || ! view.stdout || ! view.stdout.trim() ) {
		info( `⚠️  Could not reach npm to check ${ PACKAGE_NAME }. Skipping self-update.` )

		return 0
	}

	const latest = view.stdout.trim()

	if ( ! isNewer( latest, installed ) ) {
		info( `✅ ${ PACKAGE_NAME } is up to date (v${ installed }).` )

		return 0
	}

	if ( dryRun ) {
		log( `⬆️  A newer ${ PACKAGE_NAME } is available: v${ installed } -> v${ latest } (skipped in dry run).` )

		return 0
	}

	log( `⬆️  Updating ${ PACKAGE_NAME }: v${ installed } -> v${ latest }` )

	const useYarn = fs.existsSync( path.join( process.cwd(), 'yarn.lock' ) )
	const upgrade = useYarn
		? sh( `yarn upgrade ${ PACKAGE_NAME } --latest`, { stdio: 'inherit' } )
		: sh( `npm install ${ PACKAGE_NAME }@latest ${ isDev ? '--save-dev' : '--save' }`, { stdio: 'inherit' } )

	if ( ! upgrade || upgrade.status !== 0 ) {
		info( `⚠️  Upgrade of ${ PACKAGE_NAME } failed. Continuing with v${ installed }.` )

		return 0
	}

	const newVersion = readJson( installedPkgPath ).version

	if ( newVersion === installed ) {
		info( `ℹ️  ${ PACKAGE_NAME } unchanged after upgrade (still v${ installed }).` )

		return 0
	}

	const changelogChanged = updateChangelog( newVersion )

	if ( ! changelogChanged ) {
		info( '⚠️  Upgraded, but could not record a changelog entry (no NEXT_VERSION section?).' )
	}

	// Commit and push the update (wpubt-style).
	const lockFile = useYarn
		? 'yarn.lock'
		: ( fs.existsSync( path.join( process.cwd(), 'package-lock.json' ) ) ? 'package-lock.json' : '' )

	const toAdd = [ 'package.json', 'CHANGELOG.md', lockFile ].filter( Boolean ).join( ' ' )

	sh( `git add ${ toAdd }` )

	const commit = sh( `git commit -m "Update ${ PACKAGE_NAME } to v${ newVersion }"` )

	if ( commit.status === 0 ) {
		const push = sh( 'git push' )

		if ( push.status === 0 ) {
			log( `✅ Updated ${ PACKAGE_NAME } to v${ newVersion } (committed and pushed).` )
		} else {
			log( `✅ Updated ${ PACKAGE_NAME } to v${ newVersion } (committed; push failed - check remote access).` )
		}
	} else {
		info( '⚠️  Nothing committed for the build-tools update.' )
	}

	return 0
}

if ( require.main === module ) {
	try {
		process.exit( main() )
	} catch ( error ) {
		// Never let a self-update problem break a release.
		if ( process.env.DEBUG ) {
			console.error( 'ssh-update error:', error )
		}

		process.exit( 0 )
	}
}

module.exports = { parseVersion, isNewer, updateChangelog }
