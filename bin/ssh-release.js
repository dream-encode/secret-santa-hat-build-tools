#!/usr/bin/env node

/*
 * Node wrapper for ssh-release.
 *
 * Spawns the bundled bash release script so the tool works identically whether
 * it is invoked through `yarn release`, `npm run release`, or `npx ssh-release`.
 * Forcing UTF-8 locale here fixes the emoji display issues yarn causes on Windows.
 */

const { spawn } = require( 'child_process' )
const path      = require( 'path' )

const scriptDir     = __dirname
const releaseScript = path.join( scriptDir, 'release.sh' )

const isYarn    = process.env.npm_config_user_agent && process.env.npm_config_user_agent.includes( 'yarn' )
const isWindows = process.platform === 'win32'

if ( isYarn && isWindows ) {
	console.log( '⚠️  Note: running via yarn on Windows may garble emoji output. If it looks wrong, use: npm run release' )
	console.log( '' )
}

const child = spawn( 'bash', [ releaseScript, ...process.argv.slice( 2 ) ], {
	stdio: 'inherit',
	cwd: process.cwd(),
	env: {
		...process.env,
		LANG: process.env.LANG || 'en_US.UTF-8',
		LC_ALL: process.env.LC_ALL || 'en_US.UTF-8',
		PYTHONIOENCODING: 'utf-8',
		TERM: process.env.TERM || 'xterm-256color',
		SSH_RELEASE_VIA_YARN: isYarn ? '1' : '0',
	},
} )

child.on( 'error', ( err ) => {
	console.error( '❌ Failed to launch the release script.' )

	if ( err.code === 'ENOENT' ) {
		console.error( '   `bash` was not found on your PATH. Install Git Bash (Windows) or bash (macOS/Linux).' )
	} else {
		console.error( `   ${ err.message }` )
	}

	process.exit( 1 )
} )

child.on( 'exit', ( code ) => {
	process.exit( code === null ? 1 : code )
} )
