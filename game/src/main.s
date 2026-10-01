; The main loop.

	include	"config.i"
	include	"hw.i"
	include	"state.i"

	xdef	Main
	xref	VideoInit
	xref	VideoWaitFrame
	xref	VideoFlip

METER_COLOUR	equ	$004		; the raster meter's idle colour

	section	code,code

;--
; Main
; Run the game until the left mouse button is pressed (or, in a test build, for TEST_FRAMES frames).
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1, a0-a1
Main:	bsr	VideoInit
.Frame	bsr	VideoWaitFrame
	if	TEST_FRAMES
	move.w	FrameCount(a5),FrameStart(a5)
	endc

	; the frame's work goes here

	if	RASTER_METER
	move.w	#METER_COLOUR,color(a6)	; the copper sets it back at the top of the frame
	endc
	if	TEST_FRAMES
	bsr	FrameStats
	endc
	bsr	VideoFlip
	if	TEST_FRAMES
	cmp.w	#TEST_FRAMES,StatFrames(a5)
	beq	.Done
	endc
	btst	#CIAAB_FIRE0,CIAA_PRA
	bne	.Frame
.Done
	if	TEST_FRAMES
	lea	StatWorst(a5),a0
	move.l	a0,ReportPtr(a5)
	move.l	#STAT_SIZE,ReportLen(a5)
	endc
	rts

	if	TEST_FRAMES
;--
; FrameStats
; Record how many raster lines this frame's work took.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1
FrameStats:
	; lines = whole frames overrun * 313 + the line the beam is on now
	move.l	vposr(a6),d0
	lsr.l	#8,d0
	and.l	#$1ff,d0
	move.w	FrameCount(a5),d1
	sub.w	FrameStart(a5),d1
	mulu.w	#PAL_LINES,d1
	add.w	d1,d0
	cmp.w	StatWorst(a5),d0
	bls	.NotWorst
	move.w	d0,StatWorst(a5)
.NotWorst
	add.l	d0,StatTotal(a5)
	addq.w	#1,StatFrames(a5)
	rts
	endc
