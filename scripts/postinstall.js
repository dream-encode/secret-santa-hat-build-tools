#!/usr/bin/env node

/*
 * Postinstall for @secret-santa-hat/build-tools.
 *
 * After the package is installed into a project, notify that a "release"
 * script can be wired in. It never edits package.json automatically here;
 * wiring happens through the interactive `setup` command so installs stay
 * side-effect free (and CI-safe).
 */

const fs   = require( 'fs' )
const path = require( 'path' )
const { analyzeCurrentSetup, findProjectRoot } = require( './setup-project' )

const PACKAGE_NAME = '@secret-santa-hat/build-tools'

const colors = {
	green: '\x1b[32m',
	yellow: '\x1b[33m',
	blue: '\x1b[34m',
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

function isSelfInstall() {
	try {
		const pkg = JSON.parse( fs.readFileSync( path.join( process.cwd(), 'package.json' ), 'utf8' ) )

		return pkg.name === PACKAGE_NAME
	} catch {
		return false
	}
}

function shouldSkip() {
	return !! ( process.env.CI || process.env.NO_SETUP || isSelfInstall() )
}

function main() {
	if ( shouldSkip() ) {
		return
	}

	try {
		const projectRoot = findProjectRoot()

		if ( ! projectRoot ) {
			return
		}

		const pkg = JSON.parse( fs.readFileSync( path.join( projectRoot, 'package.json' ), 'utf8' ) )
		const analysis = analyzeCurrentSetup( pkg )

		if ( ! analysis.needsSetup ) {
			return
		}

		log( '\n' + '='.repeat( 60 ), 'blue' )
		log( '🎅 secret-santa-hat-build-tools installed', 'bold' )
		log( '='.repeat( 60 ), 'blue' )

		if ( analysis.hasReleaseScript ) {
			log( `\n⚠️  Existing release script detected: "${ analysis.currentReleaseScript }"`, 'yellow' )
			log( '   (setup will back it up as "release-backup")', 'dim' )
		}

		log( '\n💡 Wire in the release script with:', 'bold' )
		log( `   npx ${ PACKAGE_NAME } setup          # interactive`, 'blue' )
		log( `   npx ${ PACKAGE_NAME } setup --force  # no prompts`, 'blue' )
		log( '\n   Then: yarn release   (runs your prerelease script, then the release flow)', 'dim' )
		log( '='.repeat( 60 ) + '\n', 'blue' )

		if ( ! isInteractive() ) {
			log( `Run: npx ${ PACKAGE_NAME } setup`, 'yellow' )
		}
	} catch ( error ) {
		if ( process.env.DEBUG ) {
			console.error( 'secret-santa-hat-build-tools postinstall error:', error )
		}
	}
}

main()
