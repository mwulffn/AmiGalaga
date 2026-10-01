; The game state's storage. See include/state.i for the layout.

	include	"state.i"

	xdef	State

	section	bss,bss
State:	ds.b	State_SIZEOF
