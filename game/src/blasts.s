; Blasts: an enemy blowing up, and the score that may appear where it was.
;
; As the arcade shows it: the arcade steps each enemy's state every fourth
; frame (on frames 1, 5, 9... or 3, 7, 11... by the enemy's number), so a
; destroyed enemy is still seen for up to four frames, then come three
; 16x16 frames, two 32x32 ones centred on the same spot, and for a boss shot
; while diving its score for 19 steps. Each is drawn as a flyer. A big frame
; is one 32x32 object if all of it is inside the buffer; one that hangs over
; an edge is four flyers, which are clipped, or left out, as flyers are.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"gfx.i"

	xdef	BlastsTick
	xdef	BlastsDraw
	xref	FlyerDraw
	xref	FlyersBegin
	xref	BigBegin
	xref	BigDraw
	xref	Enemies

STEP_FRAMES	equ	4			; arcade frames between steps
SMALL_STEPS	equ	3			; steps 1 to 3: the 16x16 frames
BIG_STEPS	equ	2			; steps 4 and 5: the 32x32 frames
BLAST_STEPS	equ	1+SMALL_STEPS+BIG_STEPS	; at this step the blast is over
POPUP_STEPS	equ	19			; steps a score stays
BIG_OFFSET	equ	8			; a big frame starts this far up and left
QUADS		equ	4
WIDE_OFFSET	equ	8			; a score of two images starts this far left

	section	code,code

;--
; BlastsTick
; One arcade frame: step the blasts whose turn it is.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0
BlastsTick:
	lea	Blasts(a5),a0
	moveq	#BLASTS-1,d1
	moveq	#STEP_FRAMES-1,d2
	and.w	ArcadeFrame(a5),d2
.Blast	tst.b	bl_live(a0)
	beq	.Next
	; objects 0, 4, 8... step on frames 1, 5, 9...; objects 2, 6, 10... on 3, 7, 11...
	moveq	#1,d0
	btst	#1,bl_obj(a0)
	beq	.Turn
	moveq	#3,d0
.Turn	cmp.w	d0,d2
	bne	.Next
	addq.b	#1,bl_step(a0)
	move.b	bl_step(a0),d0
	cmp.b	#BLAST_STEPS,d0
	bcs	.Next
	bne	.Score
	tst.b	bl_popup(a0)			; the blast is over: is there a score to show?
	bpl	.Next
	bra	.Over
.Score	cmp.b	#BLAST_STEPS+POPUP_STEPS,d0
	bne	.Next
.Over	clr.b	bl_live(a0)
.Next	lea	bl_SIZEOF(a0),a0
	dbf	d1,.Blast
	rts

;--
; BlastsDraw
; Draw the blasts into the back screen. Call between FlyersBegin and the next other blit.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
BlastsDraw:
	lea	Blasts(a5),a3
	moveq	#BLASTS-1,d7
.Blast	tst.b	bl_live(a3)
	beq	.Next
	move.w	bl_x(a3),d4
	move.w	bl_y(a3),d5
	moveq	#0,d6
	move.b	bl_step(a3),d6
	bne	.Blown
	move.l	bl_image(a3),a0			; not yet: still the enemy
	bra	.One
.Blown	cmp.w	#1+SMALL_STEPS,d6
	bcc	.Big
	subq.w	#1,d6
	lsl.w	#8,d6				; FRAME_SIZE each
	lea	Enemies+GFX_BLAST,a0
	add.w	d6,a0
	bra	.One
.Big	cmp.w	#BLAST_STEPS,d6
	bcc	.Score
	bsr	BigPlace
	beq	.Next				; one object: drawn with the others of its kind below
	; four 16x16 images: top left, top right, bottom left, bottom right
	sub.w	#1+SMALL_STEPS,d6
	lsl.w	#2,d6
	add.w	#SMALL_STEPS,d6
	lsl.w	#8,d6
	subq.w	#BIG_OFFSET,d4
	subq.w	#BIG_OFFSET,d5
	moveq	#QUADS-1,d3
.Quad	move.w	d4,d0
	move.w	d5,d1
	btst	#0,d3				; counting down: 3 and 1 are the left ones
	bne	.Left
	add.w	#16,d0
.Left	btst	#1,d3				; 3 and 2 the top ones
	bne	.Top
	add.w	#16,d1
.Top	move.w	d3,d2
	eor.w	#QUADS-1,d2			; their images are in the order 0 to 3
	lsl.w	#8,d2
	add.w	d6,d2
	lea	Enemies+GFX_BLAST,a0
	add.w	d2,a0
	move.w	d3,-(sp)
	bsr	Draw
	move.w	(sp)+,d3
	dbf	d3,.Quad
	bra	.Next
.Score	moveq	#0,d6
	move.b	bl_popup(a3),d6
	cmp.w	#POPUP_WIDE,d6
	bcs	.Narrow
	; two images side by side, starting 8 pixels further left: image = 5 + 2 * (score - 5)
	add.w	d6,d6
	subq.w	#POPUP_WIDE,d6
	lsl.w	#8,d6
	lea	Enemies+GFX_POINTS,a0
	add.w	d6,a0
	move.w	d4,d0
	subq.w	#WIDE_OFFSET,d0
	move.w	d5,d1
	bsr	Draw
	lea	Enemies+GFX_POINTS+FRAME_SIZE,a0
	add.w	d6,a0
	move.w	d4,d0
	addq.w	#16-WIDE_OFFSET,d0
	move.w	d5,d1
	bsr	Draw
	bra	.Next
.Narrow	lsl.w	#8,d6
	lea	Enemies+GFX_POINTS,a0
	add.w	d6,a0
.One	move.w	d4,d0
	move.w	d5,d1
	bsr	Draw
.Next	lea	bl_SIZEOF(a3),a3
	dbf	d7,.Blast

	; the big frames that are one object each. They want the blitter set up their own way,
	; so they come after the flyers, and the flyers' set-up is put back after them
	lea	Blasts(a5),a3
	moveq	#BLASTS-1,d7
	moveq	#0,d6				; nonzero once one has been drawn
.Whole	bsr	BigPlace
	bne	.Not
	tst.w	d6
	bne	.Begun
	bsr	BigBegin
	moveq	#1,d6
.Begun	lea	Enemies+GFX_BIG_BLAST,a0
	cmp.b	#1+SMALL_STEPS,bl_step(a3)
	beq	.First
	lea	BIG_FRAME_SIZE(a0),a0
.First	bsr	BigDraw
.Not	lea	bl_SIZEOF(a3),a3
	dbf	d7,.Whole
	tst.w	d6
	bne	FlyersBegin
	rts

;--
; BigPlace
; Is a blast at one of its big frames, with all of the frame inside the buffer? Then it is
; drawn as one 32x32 object, and this is where.
; In:       a3 = the blast
; Out:      Z = yes, and then d0.w = x in buffer pixels, d1.w = y in buffer rows
; Clobbers: d0-d1
BigPlace:
	tst.b	bl_live(a3)
	beq	.No
	moveq	#-(1+SMALL_STEPS),d0
	add.b	bl_step(a3),d0
	cmp.b	#BIG_STEPS,d0
	bcc	.No
	move.w	bl_y(a3),d1
	subq.w	#BIG_OFFSET,d1
	cmp.w	#LAST_BIG_Y,d1			; unsigned: above the buffer is too high as well
	bhi	.No
	move.w	bl_x(a3),d0
	subq.w	#BIG_OFFSET,d0
	cmp.w	#LAST_BIG_X,d0
	bhi	.No
	cmp.w	d0,d0				; Z
	rts
.No	moveq	#1,d0				; not Z
	rts

;--
; Draw
; Draw one 16x16 image as a flyer if it is on the screen.
; In:       d0.w = x in buffer pixels, d1.w = y in buffer rows, a0 = image,
;           a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d3, a0-a2
Draw:	cmp.w	#LAST_FLYER_X,d0
	bhi	.Off
	cmp.w	#LAST_FLYER_Y,d1
	bls	FlyerDraw
.Off	rts
