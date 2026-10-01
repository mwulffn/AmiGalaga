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

DISPLAY_TOP	equ	44			; raster line of the first displayed line

; What goes with a screen buffer. FrontScreen and BackScreen in the state
; point at one of these each.
MAX_FLYERS	equ	32
	rsreset
scr_bitmap	rs.l	1			; the buffer, in chip RAM
scr_score	rs.l	1			; the score its panel shows
scr_flyers	rs.w	1			; flyers drawn in it, to erase next time
scr_erase	rs.l	MAX_FLYERS		;   and where
scr_SIZEOF	rs.b	0

; the formation, and the arcade's two tables that place it (HomeX, HomeLoc):
; an entry of two bytes for each of 10 columns, then each of 6 rows
FORM_ROWS	equ	5			; rows drawn as strips
FORM_SPREAD	equ	64			; how much further apart the outer columns get at most
HOME_COLUMNS	equ	10
HOME_ROWS	equ	2*HOME_COLUMNS		; offset of the first row's entry
HOME_ENTRIES	equ	HOME_COLUMNS+6		; columns and rows
STRIP_ROWS	equ	1			; the first row with a strip: row 0 is for captured fighters

; From the arcade's coordinates to the buffer's. A sprite at x, y in HomeX,
; which is how the arcade's sprite hardware counts, has its left edge at
; buffer x - SPRITE_X and its top at buffer row y - SPRITE_Y. A flight counts
; y upwards: its top is at buffer row FLIGHT_TOP - y.
SPRITE_X	equ	1
SPRITE_Y	equ	40
FLIGHT_TOP	equ	312
LAST_FLYER_X	equ	GUARD+PLAY_WIDTH-1	; a flyer further right is not on the screen
LAST_FLYER_Y	equ	SCREEN_ROWS-16		; nor one further down

; the player's fighter
SHIP_Y		equ	240			; its display line
SHIP_X_MAX	equ	PLAY_WIDTH-16
