; Text: words inside the playfield (PLAYER 1, STAGE 3, READY, GAME OVER...).
;
; Enemies fly through where the arcade writes its text, and everything
; that moves there is erased and redrawn each frame, so the text is drawn
; the same way: as flyers of half height, two letters each, built by the
; CPU from the font when a line is set and redrawn every frame while it
; shows. There are three lines.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"

	xdef	TextShow
	xdef	TextHide
	xdef	TextDraw
	xref	SmallDraw
	xref	Font

GLYPH_ROWS	equ	8
FIRST_GLYPH	equ	32			; the font starts at the space
CELL_PIXELS	equ	16			; a flyer is two letters wide
IMAGE_ROW	equ	PLANES*2		; bytes in one row of a flyer's image
MASK_OFFSET	equ	16*PLANES*2		; from a flyer's image to its mask
CELL_BYTES	equ	MASK_OFFSET+GLYPH_ROWS*IMAGE_ROW
LAST_SMALL_Y	equ	SCREEN_ROWS-GLYPH_ROWS

	section	code,code

;--
; TextShow
; Set one of the lines of text and show it from now on.
; In:       d0.w = which line, 0 to TEXT_LINES-1, a0 = the text: ASCII 32 to 90, 0 ends,
;           at most 2*TEXT_CELLS characters, d1.w = its column and d2.w = its row in the
;           playfield, in characters, d3.w = colour, a5 = state
; Out:      -
; Clobbers: d0-d2, d4-d5, a0-a3
TextShow:
	move.w	d0,d4
	mulu.w	#ts_SIZEOF,d4
	lea	TextLines(a5),a1
	add.w	d4,a1
	lsl.w	#3,d1
	add.w	#GUARD,d1
	move.w	d1,ts_x(a1)
	lsl.w	#3,d2
	add.w	#GUARD,d2
	move.w	d2,ts_y(a1)
	mulu.w	#TEXT_CELLS*CELL_BYTES,d0
	lea	TextCells,a2
	add.l	d0,a2
	moveq	#0,d5				; flyers built
.Cell	moveq	#0,d0
	move.b	(a0)+,d0
	beq	.Shown
	bsr	Glyph				; the left letter, in the high bytes
	moveq	#' ',d0
	tst.b	(a0)
	beq	.Right
	move.b	(a0)+,d0
.Right	addq.l	#1,a2
	bsr	Glyph
	lea	CELL_BYTES-1(a2),a2
	addq.w	#1,d5
	cmp.w	#TEXT_CELLS,d5
	bne	.Cell
.Shown	move.w	d5,ts_cells(a1)
	rts

;--
; Glyph
; Write one letter into half of a flyer's image and mask.
; In:       d0.w = the letter, a2 = the image, or the image + 1 for its right half,
;           d3.w = colour
; Out:      -
; Clobbers: d0-d2, a3
Glyph:	move.l	a1,-(sp)
	lea	MASK_OFFSET(a2),a1
	lsl.w	#3,d0
	lea	Font-FIRST_GLYPH*GLYPH_ROWS,a3
	add.w	d0,a3
	moveq	#0,d1				; offset in the image
.Row	move.b	(a3)+,d0
	moveq	#0,d2				; plane
.Plane	move.b	d0,(a1,d1.w)
	clr.b	(a2,d1.w)
	btst	d2,d3
	beq	.Blank
	move.b	d0,(a2,d1.w)
.Blank	addq.w	#2,d1
	addq.w	#1,d2
	cmp.w	#PLANES,d2
	bne	.Plane
	cmp.w	#GLYPH_ROWS*IMAGE_ROW,d1
	bne	.Row
	move.l	(sp)+,a1
	rts

;--
; TextHide
; Stop showing a line of text.
; In:       d0.w = which line, a5 = state
; Out:      -
; Clobbers: d0, a0
TextHide:
	mulu.w	#ts_SIZEOF,d0
	lea	TextLines(a5),a0
	clr.w	ts_cells(a0,d0.w)
	rts

;--
; TextDraw
; Draw the lines that are showing into the back screen. Call between FlyersBegin and the
; next other blit.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
TextDraw:
	lea	TextLines(a5),a3
	moveq	#0,d7				; which line
.Line	move.w	ts_cells(a3),d6
	beq	.Next
	move.w	d7,d5
	mulu.w	#TEXT_CELLS*CELL_BYTES,d5
	add.l	#TextCells,d5			; the line's first flyer
	move.w	ts_x(a3),d4
	subq.w	#1,d6
.Cell	move.w	d4,d0
	move.w	ts_y(a3),d1
	cmp.w	#LAST_FLYER_X,d0
	bhi	.Skip
	cmp.w	#LAST_SMALL_Y,d1
	bhi	.Skip
	move.l	d5,a0
	bsr	SmallDraw
.Skip	add.l	#CELL_BYTES,d5
	add.w	#CELL_PIXELS,d4
	dbf	d6,.Cell
.Next	addq.l	#ts_SIZEOF,a3
	addq.w	#1,d7
	cmp.w	#TEXT_LINES,d7
	bne	.Line
	rts

	section	chip_bss,bss_c

; TEXT_LINES x TEXT_CELLS flyers: 8 rows of image, then (where a 16-row flyer has it) the mask
TextCells:
	ds.b	TEXT_LINES*TEXT_CELLS*CELL_BYTES
