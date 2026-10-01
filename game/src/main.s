; The main loop.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	Main
	xref	VideoInit
	xref	VideoWaitFrame
	xref	VideoFlip
	xref	StarsInit
	xref	GameInit
	xref	GameFrame
	xref	PanelInit
	xref	PanelScore
	xref	PanelShips
	xref	PanelStage
	xref	SpritesInit
	xref	SpritesUpdate
	xref	SoundInit
	xref	SoundStop
	if	SOUND_TEST
	xref	SoundLog
	endc
	if	STAGE_TEST
	xref	StageLog
	endc
	if	FLIGHT_TEST
	xref	FlightTest
	endc

METER_COLOUR	equ	$004		; the raster meter's idle colour

	section	code,code

;--
; Main
; Run the game until the left mouse button is pressed (or, in a test build, for TEST_FRAMES frames).
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
Main:	bsr	StarsInit
	bsr	VideoInit
	bsr	SoundInit
	bsr	GameInit
	bsr	PanelInit
	bsr	SpritesInit
	if	FLIGHT_TEST
	bsr	FlightTest
	bra	.Done
	endc
.Frame	bsr	VideoWaitFrame
	if	TEST_FRAMES
	move.w	FrameCount(a5),FrameStart(a5)
	endc

	bsr	SpritesUpdate
	bsr	PanelScore
	bsr	PanelShips
	bsr	PanelStage
	bsr	GameFrame
	WAITBLIT				; nothing may still be drawing when the screens swap

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
.Done	bsr	SoundStop
	if	STAGE_TEST
	lea	StageLog,a0
	move.l	a0,ReportPtr(a5)
	move.l	StageLogPtr(a5),d0
	sub.l	a0,d0
	move.l	d0,ReportLen(a5)
	rts
	endc
	if	SOUND_TEST
	move.l	#SoundLog,ReportPtr(a5)
	move.l	#SOUND_TEST*SOUND_LOG_ENTRY,ReportLen(a5)
	else
	if	TEST_FRAMES
	lea	StatWorst(a5),a0
	move.l	a0,ReportPtr(a5)
	move.l	#STAT_SIZE,ReportLen(a5)
	endc
	endc
	rts

	if	TEST_FRAMES
;--
; StatLoad
; What is on screen: for the report's list of late frames.
; In:       a5 = state
; Out:      d1.w = flights flying, landed ones still drawn as flyers, bombs, blasts: a nibble each
; Clobbers: -
StatLoad:
	movem.l	d0/d2/a0,-(sp)
	moveq	#0,d1
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d0
.Flight	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.Landed
	add.w	#$1000,d1
.Landed	btst	#FLB_LANDED,fl_flags(a0)
	beq	.Next
	add.w	#$0100,d1
.Next	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Flight
	lea	Bombs(a5),a0
	moveq	#BOMBS-1,d0
.Bomb	tst.w	bm_x(a0)
	beq	.NoBomb
	add.w	#$0010,d1
.NoBomb	addq.l	#bm_SIZEOF,a0
	dbf	d0,.Bomb
	lea	Blasts(a5),a0
	moveq	#BLASTS-1,d0
.Blast	tst.b	bl_live(a0)
	beq	.NoBlast
	addq.w	#1,d1
.NoBlast
	lea	bl_SIZEOF(a0),a0
	dbf	d0,.Blast
	movem.l	(sp)+,d0/d2/a0
	rts

;--
; FrameStats
; Record how many raster lines this frame's work took.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1, a0
FrameStats:
	; lines = whole frames overrun * 313 + the line the beam is on now. The frame count
	; and the beam's line must belong together: if the vertical blank comes between
	; reading them, a frame that ended on its last line would count as two.
.Read	move.w	FrameCount(a5),d1
	move.l	vposr(a6),d0
	cmp.w	FrameCount(a5),d1
	bne	.Read
	lsr.l	#8,d0
	and.l	#$1ff,d0
	sub.w	FrameStart(a5),d1
	mulu.w	#PAL_LINES,d1
	add.w	d1,d0
	cmp.w	StatWorst(a5),d0
	bls	.NotWorst
	move.w	d0,StatWorst(a5)
	move.w	StatFrames(a5),StatWorstAt(a5)
.NotWorst
	cmp.w	#PAL_LINES,d0
	bls	.InTime
	move.w	StatOver(a5),d1
	addq.w	#1,StatOver(a5)
	cmp.w	#STAT_LATE,d1
	bcc	.InTime
	mulu.w	#6,d1
	lea	StatLate(a5),a0
	add.w	d1,a0
	move.w	StatFrames(a5),(a0)+
	move.w	d0,(a0)+
	bsr	StatLoad
	move.w	d1,(a0)
.InTime
	add.l	d0,StatTotal(a5)
	addq.w	#1,StatFrames(a5)
	rts
	endc
