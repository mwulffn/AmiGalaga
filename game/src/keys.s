; Keys: the keyboard, for the one key the game has (P, to pause).
;
; The system's keyboard handler is off while the game has the machine, so the
; keyboard is asked directly, once a frame: when CIA-A says a byte has come in
; on its serial line, that is a key going down or up. The keyboard waits for
; an answer before it sends the next one: the line held low for at least 85
; microseconds, timed here by the beam (two raster lines are 128).

	include	"config.i"
	include	"hw.i"

	xdef	KeyRead

NO_KEY		equ	-1
KEY_UP		equ	7			; a key code's bit that says the key went up
ANSWER_LINES	equ	2			; raster lines the answer lasts

	section	code,code

;--
; KeyRead
; The key that has gone down since the last call, if any.
; In:       a6 = CUSTOM
; Out:      d0.w = its raw key code, or NO_KEY
; Clobbers: d1-d2
KeyRead:
	moveq	#NO_KEY,d0
	btst	#CIA_ICR_SP,CIAA_ICR		; reading it clears it
	beq	.None
	move.b	CIAA_SDR,d1
	; the answer: the serial line is made an output, which pulls it low
	bset	#CIA_CRA_SPOUT,CIAA_CRA
	moveq	#ANSWER_LINES,d2
.Line	move.b	vhposr(a6),d0
.Same	cmp.b	vhposr(a6),d0
	beq	.Same
	dbf	d2,.Line
	bclr	#CIA_CRA_SPOUT,CIAA_CRA
	; the byte comes inverted and turned one bit round: its last bit is up or down
	moveq	#NO_KEY,d0
	not.b	d1
	ror.b	#1,d1
	btst	#KEY_UP,d1
	bne	.None
	moveq	#0,d0
	move.b	d1,d0
.None	rts
