; Formation: the enemies parked in rows at the top of the playfield.
;
; The 40 of them are not drawn one by one. Each of the five rows is a
; strip, composed off screen (a blank word, the row's enemies where the
; formation's tables put them, a slack word), and copied to the screen
; with one plain blit a frame. The copy overwrites the row's old image,
; so the formation needs no erase and no mask, and it repairs whatever a
; flyer's erase wiped. A strip is recomposed, one a frame, to follow the
; tables, the wings, and who is there.
;
; Where everything is comes from the arcade's two tables, which the
; flights read as well: HomeLoc (an offset and an origin for each of 10
; columns and 6 rows) and HomeX (origin plus offset, in pixels). The
; arcade's first row is for captured fighters and has no strip. Below the
; bosses the rows are 12 pixels apart at rest, so those strips are 12
; lines: butterflies and bees are 10 rows tall when upright.

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
CELL_WORDS	equ	2				; one enemy into a strip: its word and one for the shift
CLEAR		equ	$0100				; bltcon0: D only, all zeros
MERGE		equ	$0bfa				; bltcon0: D = A or C
COPY		equ	$09f0				; bltcon0: D = A
FIRST_WORD_ONLY	equ	$ffff0000			; bltafwm:bltalwm
IMAGE_MODULO	equ	-2
IMAGE_ROW	equ	PLANES*2			; bytes in one row of an image
PANEL_BYTE	equ	(GUARD+PLAY_WIDTH+16)/8		; a strip's copy must stop before this byte

; a row's fixed description
	rsreset
row_strip	rs.l	1				; its strip, in chip RAM
row_image	rs.l	1				; its enemy, wings open; wings closed follows
row_words	rs.w	1				; the strip's width
row_columns	rs.w	1
row_first	rs.w	1				; its first column, of the 10
row_height	rs.w	1				; the strip's height, as bltsize wants it
row_from	rs.w	1				; offset of the first image row that is copied
row_into	rs.w	1				; offset of the strip line it goes to
row_cell	rs.w	1				; bltsize for one enemy
row_dy		rs.w	1				; from a row's y in HomeX to the strip's buffer row
row_SIZEOF	rs.b	0

; a strip's width in words: blank word, the columns at their widest, slack for the shift
WORDS4		equ	(CELL+3*CELL+FORM_SPREAD+CELL+15)/16+1
WORDS8		equ	(CELL+7*CELL+FORM_SPREAD+CELL+15)/16+1
WORDS10		equ	(CELL+9*CELL+FORM_SPREAD+CELL+15)/16+1
; lines in a strip: the bosses fill their 16 rows, so their strip has a blank line above
; and below to wipe their old image when the row moves; the others bring their own
BOSS_LINES	equ	18
SMALL_LINES	equ	12

	section	code,code

;--
; FormationInit
; Put the formation at rest with nobody in it, and compose every strip.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
FormationInit:
	lea	RestTable(pc),a0
	lea	HomeX(a5),a1
	lea	HomeLoc(a5),a2
	moveq	#HOME_COLUMNS+FORM_ROWS+STRIP_ROWS-1,d0
.Home	move.b	(a0)+,d1			; where it is, in pixels
	move.b	d1,(a1)+
	clr.b	(a1)+
	clr.b	(a2)+				; no offset
	move.b	(a0)+,(a2)+			; its origin, as flights aim for it
	dbf	d0,.Home
	lea	FormPresent(a5),a0
	moveq	#FORM_ROWS-1,d0
.Empty	clr.w	(a0)+
	dbf	d0,.Empty
ROW	set	0
	rept	FORM_ROWS
	moveq	#ROW,d0
	bsr	FormationCompose
ROW	set	ROW+1
	endr
	rts

;--
; FormationCompose
; Rebuild one row's strip from the tables, the wing position and who is there, and work out where it goes.
; In:       d0.w = row, 0 to FORM_ROWS-1, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
FormationCompose:
	move.w	d0,d1
	mulu.w	#row_SIZEOF,d1
	lea	RowTable(pc),a3
	add.w	d1,a3
	move.l	row_strip(a3),a1
	move.w	row_words(a3),d1
	move.w	d1,d2
	or.w	row_height(a3),d2
	WAITBLIT
	move.l	#CLEAR<<16,bltcon0(a6)
	move.w	#0,bltdmod(a6)
	move.l	a1,bltdpt(a6)
	move.w	d2,bltsize(a6)

	; strip x = HomeX[first column] - 1 - the blank word
	; strip y = HomeX[row] - 40 + image rows skipped - blank lines above
	lea	HomeX(a5),a2
	move.w	row_first(a3),d5		; the column, from here on
	move.w	d5,d2
	add.w	d2,d2
	moveq	#0,d6
	move.b	(a2,d2.w),d6			; x of the first column
	add.w	d0,d0
	lea	FormPresent(a5),a0
	move.w	(a0,d0.w),d7			; who is there
	moveq	#0,d3
	move.b	HOME_ROWS+2*STRIP_ROWS(a2,d0.w),d3
	add.w	row_dy(a3),d3
	add.w	d0,d0
	lea	FormRows(a5),a0
	add.w	d0,a0
	move.w	d6,d2
	sub.w	#SPRITE_X+CELL,d2
	move.w	d2,(a0)+
	move.w	d3,(a0)

	move.l	row_image(a3),a0
	move.w	FrameCount(a5),d0		; wings: bit 4 of the frame count picks the image
	lsl.w	#4,d0
	and.w	#FRAME_SIZE,d0
	add.w	d0,a0
	add.w	row_from(a3),a0
	add.w	row_into(a3),a1
	add.w	d1,d1
	subq.w	#CELL_WORDS*2,d1		; the strip's modulo
	WAITBLIT
	move.l	#FIRST_WORD_ONLY,bltafwm(a6)
	move.w	#IMAGE_MODULO,bltamod(a6)
	move.w	d1,bltcmod(a6)
	move.w	d1,bltdmod(a6)
	move.w	row_columns(a3),d1
	subq.w	#1,d1
.Cell	btst	d5,d7
	beq	.Next
	; pixel in the strip = blank word + this column's x - the first column's
	move.w	d5,d2
	add.w	d2,d2
	moveq	#0,d3
	move.b	(a2,d2.w),d3
	sub.w	d6,d3
	add.w	#CELL,d3
	moveq	#15,d4
	and.w	d3,d4
	ror.w	#4,d4
	or.w	#MERGE,d4
	swap	d4
	clr.w	d4				; bltcon0:bltcon1
	lsr.w	#3,d3
	and.l	#$fffe,d3
	add.l	a1,d3				; the word in the strip
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.l	a0,bltapt(a6)
	move.l	d3,bltcpt(a6)
	move.l	d3,bltdpt(a6)
	move.w	row_cell(a3),bltsize(a6)
.Next	addq.w	#1,d5
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
	or.w	row_height(a3),d0
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

; The formation at rest, as the arcade has it: for each column, then each row,
; its position in pixels (HomeX) and the origin flights aim for (HomeLoc).
; A column's origin is its x; a row's is its height above the bottom, halved.
RestTable:
X	set	49
	rept	HOME_COLUMNS
	dc.b	X,X
X	set	X+CELL
	endr
	dc.b	60,146,76,138,92,130,104,124,116,118,128,112
	even

; \1 = strip, \2 = GFX_ name, \3 = width in words, \4 = columns, \5 = first column,
; \6 = lines in the strip, \7 = image rows copied, \8 = the first of them, \9 = the strip line it goes to
ROW	macro
	dc.l	\1,Enemies+\2+6*FRAME_SIZE
	dc.w	\3,\4,\5,(\6*PLANES)<<6
	dc.w	\8*IMAGE_ROW,\9*PLANES*\3*2,(\7*PLANES)<<6|CELL_WORDS,\8-\9-SPRITE_Y
	endm

RowTable:
	ROW	Strip0,GFX_BOSS,WORDS4,4,3,BOSS_LINES,16,0,1
	ROW	Strip1,GFX_BUTTERFLY,WORDS8,8,1,SMALL_LINES,12,2,0
	ROW	Strip2,GFX_BUTTERFLY,WORDS8,8,1,SMALL_LINES,12,2,0
	ROW	Strip3,GFX_BEE,WORDS10,10,0,SMALL_LINES,12,2,0
	ROW	Strip4,GFX_BEE,WORDS10,10,0,SMALL_LINES,12,2,0

	section	chip_bss,bss_c

Strip0:	ds.w	WORDS4*BOSS_LINES*PLANES
Strip1:	ds.w	WORDS8*SMALL_LINES*PLANES
Strip2:	ds.w	WORDS8*SMALL_LINES*PLANES
Strip3:	ds.w	WORDS10*SMALL_LINES*PLANES
Strip4:	ds.w	WORDS10*SMALL_LINES*PLANES
