#!/usr/bin/env node

/*
 * Project setup for @secret-santa-hat/build-tools.
 *
 * Wires a "release": "ssh-release" script into the consuming project's
 * package.json. Any existing custom release script is backed up as
 * "release-backup". An existing "prerelease" script is never touched, so the
 * per-repo prerelease step keeps running before release.
 */

const fs       = require( 'fs' )
const path     = require( 'path' )
const readline = require( 'readline' )

const PACKAGE_NAME  = '@secret-santa-hat/build-tools'
const RELEASE_VALUE = 'ssh-release'

const VALID_RELEASE_SCRIPTS = [
	'ssh-release',
	'npx ssh-release',
	`npx ${ PACKAGE_NAME }`,
]

const colors = {
	green: '\x1b[32m',
	yellow: '\x1b[33m',
	blue: '\x1b[34m',
	red: '\x1b[31m',
	reset: '\x1b[0m',
	bold: '\x1b[1m',
	dim: '\x1b[2m',
}

function log( message, color = 'reset' ) {
	console.log( `${ colors[ color ] }${ message }${ colors.reset }` )
}

function isInteractive() {
	return process.stdout.isTTY && process.stdin.isTTY && ! process.env.CI
}

function findProjectRoot() {
	let currentDir = process.cwd()

	while ( currentDir !== path.dirname( currentDir ) ) {
		if ( fs.existsSync( path.join( currentDir, 'package.json' ) ) ) {
			return currentDir
		}

		currentDir = path.dirname( currentDir )
	}

	return null
}

function readPackageJson( projectRoot ) {
	try {
		return JSON.parse( fs.readFileSync( path.join( projectRoot, 'package.json' ), 'utf8' ) )
	} catch ( error ) {
		log( `❌ Error reading package.json: ${ error.message }`, 'red' )

		return null
	}
}

function writePackageJson( projectRoot, packageData ) {
	try {
		fs.writeFileSync(
			path.join( projectRoot, 'package.json' ),
			JSON.stringify( packageData, null, 2 ) + '\n',
			'utf8'
		)

		return true
	} catch ( error ) {
		log( `❌ Error writing package.json: ${ error.message }`, 'red' )

		return false
	}
}

function analyzeCurrentSetup( pkg ) {
	const releaseScript      = pkg.scripts && pkg.scripts.release
	const isReleaseConfigured = !! ( releaseScript && VALID_RELEASE_SCRIPTS.includes( releaseScript.trim() ) )

	return {
		hasReleaseScript: !! releaseScript,
		currentReleaseScript: releaseScript,
		isReleaseConfigured,
		hasPreflight: !! ( pkg.scripts && pkg.scripts.preflight ),
		hasLegacyPrerelease: !! ( pkg.scripts && pkg.scripts.prerelease ),
		needsSetup: ! isReleaseConfigured,
	}
}

function promptUser( question ) {
	return new Promise( ( resolve ) => {
		const rl = readline.createInterface( { input: process.stdin, output: process.stdout } )

		rl.question( question, ( answer ) => {
			rl.close()
			resolve( answer.toLowerCase().trim() )
		} )
	} )
}

async function setupReleaseScript( projectRoot, pkg, analysis, force = false ) {
	log( '\n🔧 secret-santa-hat-build-tools setup', 'bold' )
	log( '=====================================', 'blue' )

	if ( analysis.isReleaseConfigured ) {
		log( '✅ Release script already configured: "release": "ssh-release"', 'green' )

		return true
	}

	log( '\n📋 Proposed changes:', 'bold' )

	if ( analysis.hasReleaseScript ) {
		log( `   • Back up existing release script: "${ analysis.currentReleaseScript }" -> "release-backup"`, 'yellow' )
	}

	log( `   • Set "release": "${ RELEASE_VALUE }"`, 'blue' )

	if ( analysis.hasLegacyPrerelease ) {
		log( '   • Rename your "prerelease" script to "preflight" - ssh-release runs it with output captured (quiet on pass, shown on failure)', 'yellow' )
	} else if ( analysis.hasPreflight ) {
		log( '   • Your "preflight" script will run before each release (output captured)', 'dim' )
	} else {
		log( '   • Tip: add a "preflight" script (tests/lint/build) - ssh-release runs it before each release, quietly', 'dim' )
	}

	if ( ! force && isInteractive() ) {
		log( '\n❓ Proceed with setup?', 'bold' )
		const answer = await promptUser( '   Type "yes" to continue, anything else to skip: ' )

		if ( answer !== 'yes' && answer !== 'y' ) {
			log( '\n⏭️  Setup skipped. Run it later with:', 'yellow' )
			log( `   npx ${ PACKAGE_NAME } setup`, 'blue' )

			return false
		}
	}

	if ( ! pkg.scripts ) {
		pkg.scripts = {}
	}

	if ( analysis.hasReleaseScript && ! analysis.isReleaseConfigured ) {
		pkg.scripts[ 'release-backup' ] = analysis.currentReleaseScript
		log( '   ✅ Backed up existing release script to "release-backup"', 'green' )
	}

	pkg.scripts.release = RELEASE_VALUE

	if ( writePackageJson( projectRoot, pkg ) ) {
		log( '   ✅ package.json updated.', 'green' )
		log( '\n🎉 Setup complete. You can now run:', 'bold' )
		log( '   yarn release        # or: npm run release', 'blue' )
		log( '   ssh-release --help  # all options', 'blue' )

		return true
	}

	return false
}

async function main() {
	const args  = process.argv.slice( 2 )
	const force = args.includes( '--force' ) || args.includes( '-f' )
	const quiet = args.includes( '--quiet' ) || args.includes( '-q' )

	if ( ! quiet ) {
		log( '🚀 secret-santa-hat-build-tools project setup\n', 'bold' )
	}

	const projectRoot = findProjectRoot()

	if ( ! projectRoot ) {
		log( '❌ No package.json found in this or any parent directory.', 'red' )
		process.exit( 1 )
	}

	const pkg = readPackageJson( projectRoot )

	if ( ! pkg ) {
		process.exit( 1 )
	}

	const analysis = analyzeCurrentSetup( pkg )

	if ( ! analysis.needsSetup && ! force ) {
		if ( ! quiet ) {
			log( '✅ Project already configured correctly.', 'green' )
		}

		process.exit( 0 )
	}

	const success = await setupReleaseScript( projectRoot, pkg, analysis, force )
	process.exit( success ? 0 : 1 )
}

process.on( 'uncaughtException', ( error ) => {
	log( `❌ Unexpected error: ${ error.message }`, 'red' )
	process.exit( 1 )
} )

if ( require.main === module ) {
	main().catch( ( error ) => {
		log( `❌ Setup failed: ${ error.message }`, 'red' )
		process.exit( 1 )
	} )
}

module.exports = { setupReleaseScript, analyzeCurrentSetup, findProjectRoot }
