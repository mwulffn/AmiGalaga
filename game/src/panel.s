; Panel: the score panel at the right of the playfield, and text.
;
; Text is drawn by the CPU, only when it changes, straight into a screen
; buffer. Printing writes only the bitplanes its colour uses, so a
; character cell must keep one colour for good; that holds for the panel.
; Text inside the playfield will be flyers, not this.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"sound.i"
	include	"state.i"
	include	"gfx.i"

	xdef	PanelInit
	xdef	PanelScore
	xref	Font
	xref	Enemies

PANEL		equ	VISIBLE+(PLAY_WIDTH+16)/8	; the panel's top left byte in a buffer
GLYPH_ROWS	equ	8
FIRST_GLYPH	equ	32				; the font starts at the space
ICON_WORDS	equ	16*PLANES			; a 16x16 image, one word a plane row
WHITE		equ	1				; palette entries
RED		equ	2
YELLOW		equ	3
SCORE_AT	equ	PANEL+50*ROW_BYTES+2
SHIPS_AT	equ	PANEL+232*ROW_BYTES
NO_SCORE	equ	-1				; scr_score: nothing drawn yet
ASCII_ZERO	equ	'0'

	section	code,code

;--
; PanelInit
; Draw the panel's fixed text and the spare fighters into both screens.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a3
PanelInit:
	move.l	FrontScreen(a5),a3
	bsr	PanelDraw
	move.l	BackScreen(a5),a3
	; falls through

;--
; PanelDraw
; Draw the panel's fixed contents into one screen, and mark its score as not drawn.
; In:       a3 = the screen (a scr_ structure)
; Out:      -
; Clobbers: d0-d3, a0-a3
PanelDraw:
	moveq	#NO_SCORE,d0
	move.l	d0,scr_score(a3)
	move.l	scr_bitmap(a3),a3
	lea	Labels(pc),a0
.Label	move.w	(a0)+,d0			; colour; 0 ends the list
	beq	.Icons
	move.l	a3,a1
	add.l	(a0)+,a1
	bsr	TextPrint
	move.l	a0,d1				; a label's text is padded to an even length
	addq.l	#1,d1
	and.w	#$fffe,d1
	move.l	d1,a0
	bra	.Label
.Icons	lea	SHIPS_AT,a1
	add.l	a3,a1
	bsr	Icon
	lea	SHIPS_AT+2,a1
	add.l	a3,a1
	; falls through

;--
; Icon
; Copy a spare fighter to a word-aligned position in a screen buffer.
; In:       a1 = the screen position
; Out:      -
; Clobbers: d0, a0-a1
Icon:	lea	Enemies+GFX_FIGHTER+6*FRAME_SIZE,a0
	moveq	#ICON_WORDS-1,d0
.Word	move.w	(a0)+,(a1)
	lea	PLANE_BYTES(a1),a1
	dbf	d0,.Word
	rts

;--
; PanelScore
; Bring the back screen's score up to date, if it is not.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a2
PanelScore:
	move.l	BackScreen(a5),a2
	move.l	Score(a5),d0
	cmp.l	scr_score(a2),d0
	beq	.Fresh
	move.l	d0,scr_score(a2)
	lea	Score+1(a5),a0			; three bytes of two decimal digits each
	lea	ScoreText(a5),a1
	moveq	#3-1,d1
.Digits	move.b	(a0)+,d2
	move.b	d2,d3
	lsr.b	#4,d2
	and.b	#15,d3
	add.b	#ASCII_ZERO,d2
	add.b	#ASCII_ZERO,d3
	move.b	d2,(a1)+
	move.b	d3,(a1)+
	dbf	d1,.Digits
	clr.b	(a1)
	lea	ScoreText(a5),a0
	move.l	scr_bitmap(a2),a1
	add.l	#SCORE_AT,a1
	moveq	#WHITE,d0
	bsr	TextPrint
.Fresh	rts

;--
; TextPrint
; Print text at a byte position in a screen buffer.
; In:       a0 = text: ASCII 32 to 90, 0 ends, a1 = the screen byte of the first character,
;           d0 = colour
; Out:      a0 = after the text's terminator
; Clobbers: d1-d3, a1-a2
TextPrint:
.Char	moveq	#0,d1
	move.b	(a0)+,d1
	beq	.Done
	lsl.w	#3,d1
	lea	Font-FIRST_GLYPH*GLYPH_ROWS,a2
	add.w	d1,a2
	moveq	#0,d3				; plane
.Plane	btst	d3,d0
	beq	.Skip
	moveq	#GLYPH_ROWS-1,d2
.Row	move.b	(a2)+,(a1)
	lea	ROW_BYTES(a1),a1
	dbf	d2,.Row
	subq.l	#GLYPH_ROWS,a2
	lea	-GLYPH_ROWS*ROW_BYTES(a1),a1
.Skip	lea	PLANE_BYTES(a1),a1
	addq.w	#1,d3
	cmp.w	#PLANES,d3
	bne	.Plane
	lea	1-PLANES*PLANE_BYTES(a1),a1	; the next character cell
	bra	.Char
.Done	rts

; \1 = colour, \2 = display row, \3 = character column in the panel, \4 = text
LABEL	macro
	dc.w	\1
	dc.l	PANEL+\2*ROW_BYTES+\3
	dc.b	\4,0
	even
	endm

Labels:	LABEL	RED,8,0,"HIGH SCORE"
	LABEL	WHITE,18,2,"020000"
	LABEL	RED,40,0,"1UP"
	LABEL	YELLOW,216,0,"SHIPS"
	dc.w	0
