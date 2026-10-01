; Screen layout. A buffer is 336 x 288 pixels, 4 bitplanes interleaved:
;
;   x    0..15   hidden guard column
;       16..239  playfield (display x 0..223)
;      240..255  black gap, also a guard column
;      256..335  panel, 10 characters
;   y    0..15   hidden guard rows
;       16..271  the 256 displayed lines
;      272..287  hidden guard rows

PLANES		equ	4
PLANE_BYTES	equ	42			; bytes per bitplane row
ROW_BYTES	equ	PLANE_BYTES*PLANES	; bytes per interleaved screen row
GUARD		equ	16			; hidden rows above and below, hidden pixels left
DISPLAY_BYTES	equ	40			; bytes per bitplane row that are shown
DISPLAY_LINES	equ	256
PLAY_WIDTH	equ	224
SCREEN_ROWS	equ	DISPLAY_LINES+2*GUARD
SCREEN_SIZE	equ	ROW_BYTES*SCREEN_ROWS
VISIBLE		equ	GUARD*ROW_BYTES+GUARD/8	; first displayed byte of a buffer
