; Panel: the score panel at the right of the playfield, and text.
;
; Text is drawn by the CPU, only when it changes, straight into a screen
; buffer. Printing writes only the bitplanes its colour uses, so a
; character cell must keep one colour for good; that holds for the panel.
; Text inside the playfield will be flyers, not this.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"gfx.i"

	xdef	PanelInit
	xdef	PanelScore
	xdef	PanelShips
	xdef	PanelStage
	xref	Badges
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
HIGH_AT		equ	PANEL+18*ROW_BYTES+2
SHIPS_AT	equ	PANEL+232*ROW_BYTES
BADGES_AT	equ	PANEL+192*ROW_BYTES
FIRST_BADGE	equ	$36				; the arcade's number of the first badge tile
BADGE_BYTES	equ	GLYPH_ROWS*PLANES		; a tile: 8 rows of 4 plane bytes
NO_SCORE	equ	-1				; scr_score: nothing drawn yet
ASCII_ZERO	equ	'0'
SHIP_PLACES	equ	5				; spare fighters the panel has room for

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
	move.l	d0,scr_high(a3)
	move.w	d0,scr_ships(a3)
	move.w	d0,scr_badges(a3)
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
.Icons	rts

;--
; PanelShips
; Bring the back screen's row of spare fighters up to date, if it is not.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a2
PanelShips:
	move.l	BackScreen(a5),a2
	moveq	#0,d3
	move.b	Lives(a5),d3
	cmp.w	scr_ships(a2),d3
	beq	.Fresh
	move.w	d3,scr_ships(a2)
	move.l	scr_bitmap(a2),a2
	add.l	#SHIPS_AT,a2
	moveq	#0,d2				; which place
.Place	move.l	a2,a1
	lea	Enemies+GFX_FIGHTER+6*FRAME_SIZE,a0
	moveq	#ICON_WORDS-1,d0
.Word	moveq	#0,d1				; a fighter if there is one for this place, else nothing
	cmp.w	d3,d2
	bcc	.Put
	move.w	(a0),d1
.Put	addq.l	#2,a0
	move.w	d1,(a1)
	lea	PLANE_BYTES(a1),a1
	dbf	d0,.Word
	addq.l	#2,a2
	addq.w	#1,d2
	cmp.w	#SHIP_PLACES,d2
	bne	.Place
.Fresh	rts

;--
; PanelScore
; Bring the back screen's score and high score up to date, if they are not.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a3
PanelScore:
	move.l	BackScreen(a5),a3
	move.l	Score(a5),d0
	cmp.l	scr_score(a3),d0
	beq	.High
	move.l	d0,scr_score(a3)
	lea	Score+1(a5),a0
	move.l	#SCORE_AT,d2
	bsr	Number
.High	move.l	HighScore(a5),d0
	cmp.l	scr_high(a3),d0
	beq	.Fresh
	move.l	d0,scr_high(a3)
	lea	HighScore+1(a5),a0
	move.l	#HIGH_AT,d2
	bsr	Number
.Fresh	rts

;--
; Number
; Print a score in the panel.
; In:       a0 = its three bytes of two decimal digits each, d2.l = where in a buffer,
;           a3 = the screen (a scr_ structure), a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a2
Number:	lea	ScoreText(a5),a1
	moveq	#3-1,d1
.Digits	move.b	(a0)+,d0
	move.b	d0,d3
	lsr.b	#4,d0
	and.b	#15,d3
	add.b	#ASCII_ZERO,d0
	add.b	#ASCII_ZERO,d3
	move.b	d0,(a1)+
	move.b	d3,(a1)+
	dbf	d1,.Digits
	clr.b	(a1)
	lea	ScoreText(a5),a0
	move.l	scr_bitmap(a3),a1
	add.l	d2,a1
	moveq	#WHITE,d0
	bra	TextPrint

;--
; PanelStage
; Bring the back screen's row of stage badges up to date, if it is not. The game reveals
; a new stage's badges one at a time (BadgeShown).
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, d4, a0-a3
PanelStage:
	move.l	BackScreen(a5),a3
	move.w	Stage(a5),d0
	lsl.w	#8,d0
	move.b	BadgeShown(a5),d0
	cmp.w	scr_badges(a3),d0
	beq	.Fresh
	move.w	d0,scr_badges(a3)
	move.l	scr_bitmap(a3),a3
	add.l	#BADGES_AT,a3
	lea	BadgeList(a5),a2
	moveq	#0,d4				; which column
.Column	lea	NoBadge(pc),a0			; a badge's two tiles, one above the other, or nothing
	cmp.b	BadgeShown(a5),d4
	bcc	.Draw
	moveq	#(1<<BADGEB_FIRST)-1,d0
	and.b	(a2,d4.w),d0
	sub.w	#FIRST_BADGE,d0
	mulu.w	#BADGE_BYTES,d0
	lea	Badges,a0
	add.w	d0,a0
.Draw	lea	(a3,d4.w),a1
	moveq	#2*GLYPH_ROWS-1,d1
.Row	moveq	#PLANES-1,d2
.Plane	move.b	(a0)+,(a1)
	lea	PLANE_BYTES(a1),a1
	dbf	d2,.Plane
	dbf	d1,.Row
	addq.w	#1,d4
	cmp.w	#BADGE_PLACES,d4
	bne	.Column
.Fresh	rts

; two blank tiles
NoBadge:
	dcb.b	2*BADGE_BYTES,0

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
	LABEL	RED,40,0,"1UP"
	LABEL	YELLOW,216,0,"SHIPS"
	dc.w	0
