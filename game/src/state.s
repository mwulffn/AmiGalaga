; The game state's storage. See include/state.i for the layout.

	include	"config.i"
	include	"sound.i"
	include	"state.i"

	xdef	State

	section	bss,bss
State:	ds.b	State_SIZEOF
