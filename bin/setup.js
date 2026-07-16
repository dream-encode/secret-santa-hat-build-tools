#!/usr/bin/env node

/*
 * Entry point for `npx @secret-santa-hat/build-tools setup`.
 * Delegates to the interactive project setup.
 */

const path = require( 'path' )

const args = process.argv.slice( 2 )

if ( args[ 0 ] === 'setup' ) {
	process.argv = [ process.argv[ 0 ], process.argv[ 1 ], ...args.slice( 1 ) ]
}

require( path.join( __dirname, '..', 'scripts', 'setup-project.js' ) )
