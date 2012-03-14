#!/usr/bin/scons

debug = ARGUMENTS.get('debug', 0)
unittest = ARGUMENTS.get('unittest', 1)

dbase = '/usr/src/d'
dmd = dbase + '/dmd/src/dmd'
dmd_flags = '-I'+dbase+'/druntime/import'
dmd_flags = dmd_flags + ' -I'+dbase+'/druntime/src'
dmd_flags = dmd_flags + ' -L-L'+dbase+'/druntime/lib'
dmd_flags = dmd_flags + ' -I'+dbase+'/phobos/'
dmd_flags = dmd_flags + ' -L-L'+dbase+'/phobos/generated/linux/release/32'

dflags = '-I'+dbase+'/druntime/src'
dflags = dflags + ' -L'+dbase+'/druntime/lib'
if debug:
	dflags = dflags + ' -g3'
if unittest:
	dflags = dflags + ' -funittest'
	dmd_flags = dmd_flags + ' -unittest'

env = Environment(
	DMD=dmd,
	DMD_FLAGS=dmd_flags
)

env.Command('newAATest', ['newAA.d', 'newAATest.d'],
	"$DMD $DMD_FLAGS $SOURCES -of$TARGET"
)
