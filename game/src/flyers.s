; Flyers: everything that moves freely over the playfield, drawn as masked
; 16x16 blitter objects. Each frame the back screen's flyers from two
; frames ago are erased with a clear blit, then this frame's are drawn.
; The screen's hidden guard column and rows mean a flyer partly off the
; left, top or bottom needs no clipping; at the right edge the blit's
; first-word mask cuts off what would show in the gap before the panel.
;
; There are two more sizes, each with its own list to erase from: half
; height (bombs, text), and 32x32 (an explosion's big frames), which is
; not clipped at all: it is only for an object wholly inside the buffer.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	FlyersErase
	xdef	FlyersBegin
	xdef	FlyerDraw
	xdef	SmallDraw
	xdef	BigBegin
	xdef	BigDraw

FLYER_ROWS	equ	16
BLIT_WORDS	equ	2				; the image's word, and one for its shift
BLIT_SIZE	equ	(FLYER_ROWS*PLANES)<<6|BLIT_WORDS
BLIT_MODULO	equ	PLANE_BYTES-BLIT_WORDS*2	; from one plane row to the next
IMAGE_MODULO	equ	-2				; an image row is one word; step back over the second
MASK_OFFSET	equ	FLYER_ROWS*PLANES*2		; from an image to its mask
CLEAR		equ	$0100				; bltcon0: D only, all zeros
COOKIE_CUT	equ	$0fca				; bltcon0: A = mask, B = image, C = D = screen
NOT_LAST_WORD	equ	$ffff0000			; bltafwm:bltalwm, masks out the mask's extra last word
LAST_UNCLIPPED	equ	GUARD+PLAY_WIDTH-16		; furthest right a flyer fits whole
; a flyer of half height: half the blit
SMALL_ROWS	equ	8
SMALL_SIZE	equ	(SMALL_ROWS*PLANES)<<6|BLIT_WORDS
; a 32x32 object: twice the rows, and an image row of two words
BIG_ROWS	equ	32
BIG_WORDS	equ	3				; the image's two words, and one for their shift
BIG_SIZE	equ	(BIG_ROWS*PLANES)<<6|BIG_WORDS
BIG_MODULO	equ	PLANE_BYTES-BIG_WORDS*2
BIG_MASK_OFFSET	equ	BIG_ROWS*PLANES*4		; from an image to its mask

	section	code,code

;--
; FlyersErase
; Clear the flyers, whole and half height, that were drawn into the back screen the last time it was drawn.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1, a0-a1
FlyersErase:
	move.l	BackScreen(a5),a0
	WAITBLIT
	move.l	#CLEAR<<16,bltcon0(a6)
	move.w	#BLIT_MODULO,bltdmod(a6)
	move.w	scr_flyers(a0),d0
	beq	.Bombs
	clr.w	scr_flyers(a0)
	lea	scr_erase(a0),a1
	subq.w	#1,d0
.Erase	move.l	(a1)+,d1
	WAITBLIT
	move.l	d1,bltdpt(a6)
	move.w	#BLIT_SIZE,bltsize(a6)
	dbf	d0,.Erase
.Bombs	move.w	scr_smalls(a0),d0
	beq	.None
	clr.w	scr_smalls(a0)
	lea	scr_small_erase(a0),a1
	subq.w	#1,d0
.Small	move.l	(a1)+,d1
	WAITBLIT
	move.l	d1,bltdpt(a6)
	move.w	#SMALL_SIZE,bltsize(a6)
	dbf	d0,.Small
.None	move.w	scr_bigs(a0),d0
	beq	.Done
	clr.w	scr_bigs(a0)
	lea	scr_big_erase(a0),a1
	subq.w	#1,d0
	WAITBLIT
	move.w	#BIG_MODULO,bltdmod(a6)
.Big	move.l	(a1)+,d1
	WAITBLIT
	move.l	d1,bltdpt(a6)
	move.w	#BIG_SIZE,bltsize(a6)
	dbf	d0,.Big
.Done	rts

;--
; FlyersBegin
; Set the blitter up for a run of FlyerDraw calls. No other blit may come between them.
; In:       a6 = CUSTOM
; Out:      -
; Clobbers: -
FlyersBegin:
	WAITBLIT
	move.l	#NOT_LAST_WORD,bltafwm(a6)
	move.w	#BLIT_MODULO,bltcmod(a6)
	move.w	#IMAGE_MODULO,bltbmod(a6)
	move.w	#IMAGE_MODULO,bltamod(a6)
	move.w	#BLIT_MODULO,bltdmod(a6)
	rts

;--
; FlyerDraw
; Draw one flyer into the back screen and remember it for erasing.
; In:       d0.w = x in buffer pixels (0 to GUARD+PLAY_WIDTH-1: 16 is the playfield's left edge),
;           d1.w = y in buffer rows (0 to SCREEN_ROWS-16: 16 is the top line),
;           a0 = image, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d3, a0-a2
FlyerDraw:
	mulu.w	#ROW_BYTES,d1
	moveq	#15,d2
	and.w	d0,d2				; shift
	moveq	#-1,d3				; first word mask: the whole image, unless
	cmp.w	#LAST_UNCLIPPED,d0		; its second word would be the gap:
	bls	.Whole
	lsl.w	d2,d3				; then drop the columns that shift into it
.Whole	ror.w	#4,d2				; shift in bits 15-12, as bltcon0 and bltcon1 want it
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	move.l	BackScreen(a5),a2
	move.l	scr_bitmap(a2),a1
	add.l	d1,a1				; destination word
	move.w	scr_flyers(a2),d0
	cmp.w	#MAX_FLYERS,d0
	bcc	.Full
	addq.w	#1,scr_flyers(a2)
	lsl.w	#2,d0
	move.l	a1,scr_erase(a2,d0.w)
	move.w	d2,d0
	or.w	#COOKIE_CUT,d0
	swap	d0
	move.w	d2,d0				; bltcon0:bltcon1
	WAITBLIT
	move.l	d0,bltcon0(a6)
	move.w	d3,bltafwm(a6)
	move.l	a0,bltbpt(a6)
	lea	MASK_OFFSET(a0),a0
	move.l	a0,bltapt(a6)
	move.l	a1,bltcpt(a6)
	move.l	a1,bltdpt(a6)
	move.w	#BLIT_SIZE,bltsize(a6)
.Full	rts

;--
; SmallDraw
; Draw a flyer of half height (8 rows: a bomb, a pair of letters) into the back screen and
; remember it for erasing. Call it between FlyersBegin and the next other blit, as FlyerDraw.
; In:       d0.w = x in buffer pixels (0 to GUARD+PLAY_WIDTH-1), d1.w = y in buffer rows
;           (0 to SCREEN_ROWS-8), a0 = image: 8 rows in a flyer's layout, its mask
;           MASK_OFFSET after it, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d3, a0-a2
SmallDraw:
	mulu.w	#ROW_BYTES,d1
	moveq	#15,d2
	and.w	d0,d2				; shift
	moveq	#-1,d3
	cmp.w	#LAST_UNCLIPPED,d0
	bls	.Whole
	lsl.w	d2,d3				; drop the columns that would show in the gap
.Whole	ror.w	#4,d2
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	move.l	BackScreen(a5),a2
	move.l	scr_bitmap(a2),a1
	add.l	d1,a1				; destination word
	move.w	scr_smalls(a2),d0
	cmp.w	#MAX_SMALLS,d0
	bcc	.Full
	addq.w	#1,scr_smalls(a2)
	lsl.w	#2,d0
	lea	scr_small_erase(a2),a2
	move.l	a1,(a2,d0.w)
	move.w	d2,d0
	or.w	#COOKIE_CUT,d0
	swap	d0
	move.w	d2,d0				; bltcon0:bltcon1
	WAITBLIT
	move.l	d0,bltcon0(a6)
	move.w	d3,bltafwm(a6)
	move.l	a0,bltbpt(a6)
	lea	MASK_OFFSET(a0),a0
	move.l	a0,bltapt(a6)
	move.l	a1,bltcpt(a6)
	move.l	a1,bltdpt(a6)
	move.w	#SMALL_SIZE,bltsize(a6)
.Full	rts

;--
; BigBegin
; Set the blitter up for a run of BigDraw calls. No other blit may come between them, and
; FlyersBegin must be called again before the next flyer is drawn.
; In:       a6 = CUSTOM
; Out:      -
; Clobbers: -
BigBegin:
	WAITBLIT
	move.w	#$ffff,bltafwm(a6)		; a flyer at the right edge may have trimmed it
	move.w	#BIG_MODULO,bltcmod(a6)
	move.w	#BIG_MODULO,bltdmod(a6)
	rts

;--
; BigDraw
; Draw one 32x32 object into the back screen and remember it for erasing. It is not clipped:
; all of it must be inside the buffer, and none of it in the gap.
; In:       d0.w = x in buffer pixels (0 to LAST_BIG_X), d1.w = y in buffer rows
;           (0 to LAST_BIG_Y), a0 = image: 32 rows of 4 planes of two words, its mask
;           BIG_MASK_OFFSET after it, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d2, a0-a2
BigDraw:
	mulu.w	#ROW_BYTES,d1
	moveq	#15,d2
	and.w	d0,d2				; shift
	ror.w	#4,d2				; in bits 15-12, as bltcon0 and bltcon1 want it
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	move.l	BackScreen(a5),a2
	move.l	scr_bitmap(a2),a1
	add.l	d1,a1				; destination word
	move.w	scr_bigs(a2),d0
	cmp.w	#MAX_BIGS,d0
	bcc	.Full
	addq.w	#1,scr_bigs(a2)
	lsl.w	#2,d0
	lea	scr_big_erase(a2),a2
	move.l	a1,(a2,d0.w)
	move.w	d2,d0
	or.w	#COOKIE_CUT,d0
	swap	d0
	move.w	d2,d0				; bltcon0:bltcon1
	WAITBLIT
	move.l	d0,bltcon0(a6)
	move.l	a0,bltbpt(a6)
	lea	BIG_MASK_OFFSET(a0),a0
	move.l	a0,bltapt(a6)
	move.l	a1,bltcpt(a6)
	move.l	a1,bltdpt(a6)
	move.w	#BIG_SIZE,bltsize(a6)
.Full	rts
