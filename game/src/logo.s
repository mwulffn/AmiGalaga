; Logo: the game's name on the title, as a picture.
;
; AMIGALAGA in block letters, drawn by tools/make_logo.py: they are the game's
; own, not the arcade's. The picture is copied into a screen once when the
; title comes and cleared from it once when the title goes. Each screen
; remembers whether it has it, as it remembers what its panel shows, so
; nothing else in the game has to say when: what is on is asked of Mode.
; Nothing else is drawn where the logo is while the title shows.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"logo.i"

	xdef	LogoDraw

LOGO_X		equ	GUARD+(PLAY_WIDTH-16*LOGO_WORDS)/2	; in the middle of the playfield
LOGO_Y		equ	GUARD+52
LOGO_AT		equ	LOGO_Y*ROW_BYTES+LOGO_X/8		; its first byte in a screen
LOGO_SIZE	equ	(LOGO_ROWS*PLANES)<<6|LOGO_WORDS
LOGO_MODULO	equ	PLANE_BYTES-LOGO_WORDS*2
COPY		equ	$09f0					; bltcon0: D = A
CLEAR		equ	$0100					; bltcon0: D only, all zeros
ALL_WORDS	equ	$ffffffff				; bltafwm:bltalwm: nothing masked
	if	LOGO_X&15
	fail	"the logo is copied without a shift: its place must be a whole word"
	endc

	section	code,code

;--
; LogoDraw
; Put the logo in the back screen if the title is on and it is not there, or take it out
; if the title is not on and it is. Call it where no run of flyers is being drawn.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0, a0-a1
LogoDraw:
	move.l	BackScreen(a5),a0
	cmp.b	#MODE_TITLE,Mode(a5)
	seq	d0
	ext.w	d0				; what the screen should have: -1 the logo, 0 nothing
	cmp.w	scr_logo(a0),d0
	beq	.Done
	move.w	d0,scr_logo(a0)
	move.l	scr_bitmap(a0),a1
	lea	LOGO_AT(a1),a1
	WAITBLIT
	move.w	#LOGO_MODULO,bltdmod(a6)
	move.l	a1,bltdpt(a6)
	tst.w	d0
	beq	.Clear
	move.l	#COPY<<16,bltcon0(a6)
	move.l	#ALL_WORDS,bltafwm(a6)
	move.w	#0,bltamod(a6)
	move.l	#Logo,bltapt(a6)
	bra	.Go
.Clear	move.l	#CLEAR<<16,bltcon0(a6)
.Go	move.w	#LOGO_SIZE,bltsize(a6)
.Done	rts

	section	chip_data,data_c

; the picture: for each line, four planes of LOGO_WORDS words
Logo:	incbin	"logo.bin"
