; Flyers: everything that moves freely over the playfield, drawn as masked
; 16x16 blitter objects. Each frame the back screen's flyers from two
; frames ago are erased with a clear blit, then this frame's are drawn.
; The screen's hidden guard column and rows mean a flyer partly off the
; left, top or bottom needs no clipping; at the right edge the blit's
; first-word mask cuts off what would show in the gap before the panel.

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

FLYER_ROWS	equ	16
BLIT_WORDS	equ	2				; the image's word, and one for its shift
BLIT_SIZE	equ	(FLYER_ROWS*PLANES)<<6|BLIT_WORDS
BLIT_MODULO	equ	PLANE_BYTES-BLIT_WORDS*2	; from one plane row to the next
IMAGE_MODULO	equ	-2				; an image row is one word; step back over the second
MASK_OFFSET	equ	FLYER_ROWS*PLANES*2		; from an image to its mask
CLEAR		equ	$0100				; bltcon0: D only, all zeros
COOKIE_CUT	equ	$0fca				; bltcon0: A = mask, B = image, C = D = screen
FIRST_WORD_ONLY	equ	$ffff0000			; bltafwm:bltalwm, masks out the mask's second word
LAST_UNCLIPPED	equ	GUARD+PLAY_WIDTH-16		; furthest right a flyer fits whole

	section	code,code

;--
; FlyersErase
; Clear the flyers that were drawn into the back screen the last time it was drawn.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0, a0-a1
FlyersErase:
	move.l	BackScreen(a5),a0
	move.w	scr_flyers(a0),d0
	beq	.None
	clr.w	scr_flyers(a0)
	lea	scr_erase(a0),a1
	subq.w	#1,d0
	WAITBLIT
	move.l	#CLEAR<<16,bltcon0(a6)
	move.w	#BLIT_MODULO,bltdmod(a6)
.Erase	move.l	(a1)+,a0
	WAITBLIT
	move.l	a0,bltdpt(a6)
	move.w	#BLIT_SIZE,bltsize(a6)
	dbf	d0,.Erase
.None	rts

;--
; FlyersBegin
; Set the blitter up for a run of FlyerDraw calls. No other blit may come between them.
; In:       a6 = CUSTOM
; Out:      -
; Clobbers: -
FlyersBegin:
	WAITBLIT
	move.l	#FIRST_WORD_ONLY,bltafwm(a6)
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
