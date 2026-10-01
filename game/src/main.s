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
	xref	DemoFrame
	xref	GameInit
	xref	GameFrame
	xref	PanelInit
	xref	PanelScore
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
	bsr	GameInit
	bsr	PanelInit
	bsr	SpritesInit
	move.w	#SHIP_X_MAX/2,ShipX(a5)
	move.l	#$00640000+100,Bullets(a5)	; until there is a game: two bullets in flight
	move.l	#$00640000+220,Bullets+4(a5)
	bsr	SoundInit
	if	FLIGHT_TEST
	bsr	FlightTest
	bra	.Done
	endc
	if	SOUND_TEST=0
	move.b	#1,Sound+SND_START(a5)	; until there is a game: the start theme
	endc
.Frame	bsr	VideoWaitFrame
	if	TEST_FRAMES
	move.w	FrameCount(a5),FrameStart(a5)
	endc

	bsr	SpritesUpdate
	bsr	PanelScore
	bsr	DemoFrame
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
