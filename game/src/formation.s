; Formation: the enemies parked in rows at the top of the playfield.
;
; The 40 of them are not drawn one by one. Each of the five rows is a
; strip, composed off screen (a blank word, the enemies at the current
; pitch, a slack word), and copied to the screen with one plain blit a
; frame. The copy overwrites the row's old image, so the formation needs
; no erase and no mask, and it repairs whatever a flyer's erase wiped.
; A strip is recomposed when the row's pitch or wing position changes.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"gfx.i"

	xdef	FormationInit
	xdef	FormationCompose
	xdef	FormationDraw
	xref	Enemies

CELL		equ	16				; an enemy's width and height
STRIP_LINES	equ	CELL*PLANES			; a strip's height as the blitter counts it
COLUMNS		equ	10				; the formation is 10 columns wide
; x of the leftmost column's strip, before sway: centred, less the strip's blank word
FORM_X		equ	GUARD+PLAY_WIDTH/2-FORM_SWAY/2-CELL/2-CELL
FORM_Y		equ	GUARD+20			; the top row
CELL_BLIT	equ	STRIP_LINES<<6|2		; one enemy into a strip: its word and one for the shift
CLEAR		equ	$0100				; bltcon0: D only, all zeros
MERGE		equ	$0bfa				; bltcon0: D = A or C
COPY		equ	$09f0				; bltcon0: D = A
FIRST_WORD_ONLY	equ	$ffff0000			; bltafwm:bltalwm
IMAGE_MODULO	equ	-2
PANEL_BYTE	equ	(GUARD+PLAY_WIDTH+16)/8		; a strip's copy must stop before this byte

; a row's fixed description
	rsreset
row_strip	rs.l	1				; its strip, in chip RAM
row_image	rs.l	1				; its enemy, wings open; wings closed follows
row_words	rs.w	1				; the strip's width
row_columns	rs.w	1
row_first	rs.w	1				; its first column, of the 10
row_index	rs.w	1
row_SIZEOF	rs.b	0				; 16: FormationCompose shifts by 4

; a strip's width in words: blank word, the columns at the widest pitch, slack for the shift
WORDS4		equ	(CELL+3*(CELL+FORM_SPREAD_MAX)+CELL+15)/16+1
WORDS8		equ	(CELL+7*(CELL+FORM_SPREAD_MAX)+CELL+15)/16+1
WORDS10		equ	(CELL+9*(CELL+FORM_SPREAD_MAX)+CELL+15)/16+1

	section	code,code

;--
; FormationInit
; Compose every strip.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d5, a0-a3
FormationInit:
	moveq	#FORM_ROWS-1,d5
.Row	move.w	d5,d0
	bsr	FormationCompose
	dbf	d5,.Row
	rts

;--
; FormationCompose
; Rebuild one row's strip at the current spread and wing position, and work out where it goes.
; In:       d0.w = row, 0 to FORM_ROWS-1, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d4, a0-a3
FormationCompose:
	move.w	d0,d1
	lsl.w	#4,d1
	lea	RowTable(pc),a3
	add.w	d1,a3
	lsl.w	#2,d0
	lea	FormRows(a5),a2
	add.w	d0,a2				; this row's x and y
	move.l	row_strip(a3),a1
	move.w	row_words(a3),d0
	move.w	d0,d1
	or.w	#STRIP_LINES<<6,d1
	WAITBLIT
	move.l	#CLEAR<<16,bltcon0(a6)
	move.w	#0,bltdmod(a6)
	move.l	a1,bltdpt(a6)
	move.w	d1,bltsize(a6)

	; pitch = 16 + spread
	; x = FORM_X + first * pitch - 9 * pitch / 2
	; y = FORM_Y + 16 * row + row * spread / 4
	moveq	#CELL,d2
	add.w	FormSpread(a5),d2
	move.w	d2,d1
	mulu.w	#COLUMNS-1,d1
	lsr.w	#1,d1
	move.w	row_first(a3),d3
	mulu.w	d2,d3
	sub.w	d1,d3
	add.w	#FORM_X,d3
	move.w	d3,(a2)+
	move.w	row_index(a3),d3
	move.w	FormSpread(a5),d1
	mulu.w	d3,d1
	lsr.w	#2,d1
	lsl.w	#4,d3
	add.w	d3,d1
	add.w	#FORM_Y,d1
	move.w	d1,(a2)

	move.l	row_image(a3),a0
	move.w	FrameCount(a5),d1		; wings: bit 4 of the frame count picks the image
	lsl.w	#4,d1
	and.w	#FRAME_SIZE,d1
	add.w	d1,a0
	add.w	d0,d0
	subq.w	#4,d0				; the strip's modulo for a 2-word blit
	WAITBLIT
	move.l	#FIRST_WORD_ONLY,bltafwm(a6)
	move.w	#IMAGE_MODULO,bltamod(a6)
	move.w	d0,bltcmod(a6)
	move.w	d0,bltdmod(a6)
	moveq	#CELL,d3			; pixel position in the strip, after the blank word
	move.w	row_columns(a3),d1
	subq.w	#1,d1
.Cell	move.w	d3,d0
	lsr.w	#3,d0
	and.w	#$fffe,d0
	lea	(a1,d0.w),a2
	moveq	#15,d4
	and.w	d3,d4
	ror.w	#4,d4
	or.w	#MERGE,d4
	swap	d4
	clr.w	d4				; bltcon0:bltcon1
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.l	a0,bltapt(a6)
	move.l	a2,bltcpt(a6)
	move.l	a2,bltdpt(a6)
	move.w	#CELL_BLIT,bltsize(a6)
	add.w	d2,d3
	dbf	d1,.Cell
	rts

;--
; FormationDraw
; Copy the strips into the back screen: draws the formation and erases where it was.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d5, a0-a3
FormationDraw:
	lea	RowTable(pc),a3
	lea	FormRows(a5),a2
	move.l	BackScreen(a5),a0
	move.l	scr_bitmap(a0),a0
	moveq	#FORM_ROWS-1,d5
	WAITBLIT
	moveq	#-1,d0
	move.l	d0,bltafwm(a6)
.Row	move.w	(a2)+,d0
	add.w	FormSway(a5),d0
	move.w	(a2)+,d1
	mulu.w	#ROW_BYTES,d1
	moveq	#15,d4
	and.w	d0,d4
	ror.w	#4,d4
	or.w	#COPY,d4
	swap	d4
	clr.w	d4				; bltcon0:bltcon1
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	lea	(a0,d1.l),a1
	moveq	#PANEL_BYTE,d3
	sub.w	d0,d3
	lsr.w	#1,d3				; words left before the panel
	move.w	row_words(a3),d0
	move.w	d0,d2
	cmp.w	d3,d0
	bls	.Fits
	move.w	d3,d0				; drop the strip's blank tail
.Fits	sub.w	d0,d2
	add.w	d2,d2				; the strip's modulo
	moveq	#PLANE_BYTES,d3
	sub.w	d0,d3
	sub.w	d0,d3				; the screen's modulo
	or.w	#STRIP_LINES<<6,d0
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.w	d2,bltamod(a6)
	move.w	d3,bltdmod(a6)
	move.l	row_strip(a3),bltapt(a6)
	move.l	a1,bltdpt(a6)
	move.w	d0,bltsize(a6)
	lea	row_SIZEOF(a3),a3
	dbf	d5,.Row
	rts

; \1 = strip, \2 = GFX_ name, \3 = width in words, \4 = columns, \5 = first column, \6 = row
ROW	macro
	dc.l	\1,Enemies+\2+6*FRAME_SIZE
	dc.w	\3,\4,\5,\6
	endm

RowTable:
	ROW	Strip0,GFX_BOSS,WORDS4,4,3,0
	ROW	Strip1,GFX_BUTTERFLY,WORDS8,8,1,1
	ROW	Strip2,GFX_BUTTERFLY,WORDS8,8,1,2
	ROW	Strip3,GFX_BEE,WORDS10,10,0,3
	ROW	Strip4,GFX_BEE,WORDS10,10,0,4

	section	chip_bss,bss_c

Strip0:	ds.w	WORDS4*STRIP_LINES
Strip1:	ds.w	WORDS8*STRIP_LINES
Strip2:	ds.w	WORDS8*STRIP_LINES
Strip3:	ds.w	WORDS10*STRIP_LINES
Strip4:	ds.w	WORDS10*STRIP_LINES
