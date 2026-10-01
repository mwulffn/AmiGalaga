; Stage: which enemies a stage sends in, and when.
;
; A port of the arcade's wave set-up and launcher. A stage's row of data
; names, for each of its five waves, the entry path of each half of the
; wave. StageInit turns that into a table of (control, object) pairs,
; first half and second half alternately, each wave after a start mark.
; StageTick, once per arcade frame, launches at most one enemy: a wave
; starts once nothing is flying; an enemy whose control byte has bit 7
; clear waits for the arcade's frame count to reach a multiple of 8, and
; one with bit 7 set follows on the next frame. So a wave arrives as four
; pairs side by side, or as eight in a line. The model is motion/waves.py.
;
; Not built yet: the extra enemies that fly through without joining the
; formation, from stage 4 on.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"gfx.i"

	xdef	StageInit
	xdef	StageTick
	xdef	StageIdle
	xref	FormationInit
	xref	DivesInit
	xref	FlightLaunch
	xref	EntryPaths
	xref	StartPos
	xref	StageIndex
	xref	ChallengeIndex
	xref	StageData
	xref	ChallengeData
	xref	WaveObjects
	xref	EntryBombers

WAVE_START	equ	$7e			; marks in the wave table
WAVE_END	equ	$7f
CTLB_NOW	equ	7			; control byte: follows its partner at once
CTLB_MIRROR	equ	6			;   flies the path mirrored
PATH_MASK	equ	$3f			;   and which entry path
LINE_FRAMES	equ	8			; arcade frames between enemies in a line
LAST_STAGE	equ	$17			; stages from here on repeat the four before
STAGE_SLOTS	equ	17			; stages in a rank's row of the stage index
CHALLENGES	equ	8			; challenging stages before they repeat
HALF_WAVE	equ	4
; object / 2 of the first of each group
BEES		equ	$08/2
BOSSES		equ	$30/2
BUTTERFLIES	equ	$40/2
FIRST_ENEMY	equ	$08			; the first object that is a stage's enemy
TIMER_FRAMES	equ	32			; arcade frames per count of WaveTimer
WAVE_GAP	equ	2			; WaveTimer while anything is flying
WAVE_SIZE	equ	8
CHALLENGE_MASK	equ	3			; a stage whose number ends in these two bits set is a challenging stage

	section	code,code

;--
; StageInit
; Set a stage up: the formation empty and at rest, nothing flying, its waves ready to launch.
; In:       d0.w = stage, 1 for the first, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
StageInit:
	move.w	d0,Stage(a5)
	; stages past the last repeat the last four; every fourth is a challenging stage
	move.w	d0,d1
.Wrap	cmp.w	#LAST_STAGE,d1
	bcs	.Known
	subq.w	#4,d1
	bra	.Wrap
.Known	moveq	#0,d2
	moveq	#3,d3
	and.w	d1,d3
	subq.w	#3,d3
	beq	.Challenge
	; row = StageData + StageIndex[rank][stage - stage / 4 - 1]
	move.w	d1,d3
	lsr.w	#2,d3
	sub.w	d3,d1
	lea	StageIndex+RANK*STAGE_SLOTS-1(pc),a0
	move.b	(a0,d1.w),d2
	lea	StageData(pc),a0
	moveq	#KIND_BEE,d4
	moveq	#KIND_BUTTERFLY,d5
	bra	.Row
	; row = ChallengeData + ChallengeIndex[stage / 4 mod 8], and all but the bosses look alike
.Challenge
	lsr.w	#2,d0
	and.w	#CHALLENGES-1,d0
	lea	ChallengeIndex(pc),a0
	move.b	(a0,d0.w),d2
	lea	ChallengeKinds(pc),a1
	move.b	(a1,d0.w),d4
	move.b	d4,d5
	lea	ChallengeData(pc),a0
.Row	lea	(a0,d2.w),a0
	move.b	(a0)+,BombReload(a5)		; the row starts with two bytes about bombs
	move.b	(a0)+,EntryBombs(a5)

	lea	ObjKind(a5),a1
	moveq	#BEES-1,d0
.Fighters
	move.b	#KIND_FIGHTER,(a1)+
	dbf	d0,.Fighters
	moveq	#BOSSES-BEES-1,d0
.Bees	move.b	d4,(a1)+
	dbf	d0,.Bees
	moveq	#BUTTERFLIES-BOSSES-1,d0
.Bosses	move.b	#KIND_BOSS,(a1)+
	dbf	d0,.Bosses
	moveq	#OBJECTS/2-BUTTERFLIES-1,d0
.Butterflies
	move.b	d5,(a1)+
	dbf	d0,.Butterflies

	; each wave: its objects are the next 8 of WaveObjects, 4 for each half
	lea	WaveTable(a5),a1
	lea	WaveObjects(pc),a2
	moveq	#STAGE_WAVES-1,d0
.Wave	move.b	#WAVE_START,(a1)+
	addq.l	#1,a0				; enemies that only fly through: not built yet
	move.b	(a0)+,d1
	move.b	(a0)+,d2
	moveq	#HALF_WAVE-1,d3
.Pair	move.b	d1,(a1)+
	move.b	(a2),(a1)+
	move.b	d2,(a1)+
	move.b	HALF_WAVE(a2),(a1)+
	addq.l	#1,a2
	dbf	d3,.Pair
	addq.l	#HALF_WAVE,a2
	dbf	d0,.Wave
	move.b	#WAVE_END,(a1)
	clr.w	WaveAt(a5)
	clr.w	WasFlying(a5)
	clr.w	StageWait(a5)
	clr.b	WavesIn(a5)
	if	SOUND_TEST=0			; the sound test makes its own requests
	clr.b	Sound+SND_PULSE(a5)
	endc

	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d0
.Slot	clr.b	fl_flags(a0)
	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Slot
	bsr	DivesInit
	bra	FormationInit

; what a challenging stage's enemies look like, by stage / 4 mod 8
ChallengeKinds:
	dc.b	KIND_BEE,KIND_BUTTERFLY,KIND_DRAGONFLY,KIND_BOSCONIAN
	dc.b	KIND_SATELLITE,KIND_GALAXIAN,KIND_SCORPION,KIND_ENTERPRISE

;--
; StageIdle
; No stage: nothing flying, nothing to launch, the formation empty. For a game's opening.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
StageIdle:
	move.b	#WAVE_END,WaveTable(a5)
	clr.w	WaveAt(a5)
	clr.w	WasFlying(a5)
	clr.b	WavesIn(a5)
	clr.b	Alive(a5)
	clr.b	FormDirty(a5)
	if	SOUND_TEST=0
	clr.b	Sound+SND_PULSE(a5)
	endc
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d0
.Slot	clr.b	fl_flags(a0)
	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Slot
	bra	FormationInit

;--
; StageTick
; One arcade frame of the launcher: send the next enemy in if it is time.
; In:       d6.w = when in this displayed frame the arcade frame begins, in fifths,
;           a5 = state
; Out:      Z = the stage's waves have all been launched
; Clobbers: d0-d5, d7, a0-a2
StageTick:
	; how many are flying, and the first free slot
	lea	Flights(a5),a0
	sub.l	a1,a1
	moveq	#0,d0
	moveq	#FLIGHT_SLOTS-1,d1
.Slot	move.b	fl_flags(a0),d2
	btst	#FLB_ACTIVE,d2
	beq	.Idle
	addq.w	#1,d0
	bra	.Next
.Idle	btst	#FLB_LANDED,d2
	bne	.Next
	move.l	a1,d3
	bne	.Next
	move.l	a0,a1
.Next	lea	fl_SIZEOF(a0),a0
	dbf	d1,.Slot
	; the arcade hears of a landing one frame late
	move.w	WasFlying(a5),d1
	move.w	d0,WasFlying(a5)
	move.w	d1,Flying(a5)
	; the timer that spaces a challenging stage's waves counts down every 32 arcade frames
	move.b	WaveTimer(a5),d5		; as it was: what this frame goes by
	moveq	#TIMER_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Timed
	tst.b	d5
	beq	.Timed
	subq.b	#1,WaveTimer(a5)
.Timed

	lea	WaveTable(a5),a2
	add.w	WaveAt(a5),a2
	move.b	(a2)+,d0
	cmp.b	#WAVE_START,d0
	bne	.Enemy
	tst.b	InPlay(a5)			; no wave starts while the fighter is being replaced,
	beq	.Wait
	tst.w	d1				; or while anything is flying
	beq	.Clear
	move.b	#WAVE_GAP,WaveTimer(a5)
	bra	.Wait
	; a challenging stage waits the timer out as well, and sets the wave's count for its bonus
.Clear	moveq	#CHALLENGE_MASK,d0
	and.w	Stage(a5),d0
	subq.w	#CHALLENGE_MASK,d0
	bne	.Start
	cmp.b	#1,d5
	bne	.Gap
	move.b	#WAVE_SIZE,WaveHits(a5)
	bra	.Wait
.Gap	tst.b	d5
	bne	.Wait
.Start	addq.w	#1,WaveAt(a5)
.Wait	moveq	#1,d0
	rts
.Enemy	cmp.b	#WAVE_END,d0
	bne	.Launch
	tst.w	d1				; the last wave has landed: the formation can settle
	bne	.Over
	st	WavesIn(a5)
.Over	moveq	#0,d0
	rts
.Launch
	btst	#CTLB_NOW,d0
	bne	.Now
	moveq	#LINE_FRAMES-1,d1
	and.w	ArcadeFrame(a5),d1
	bne	.Wait
.Now	move.l	a1,d1
	beq	.Wait				; all twelve slots are flying
	move.l	a1,a0
	addq.w	#2,WaveAt(a5)
	moveq	#0,d4
	move.b	(a2),d4				; the object
	move.b	d0,d7				; the control byte, for after the launch
	addq.b	#1,Alive(a5)
	LOG	#STAGE_LAUNCHED,d4
	; EntryPaths[path] = script, pair of start positions; a pair is plain then mirrored
	moveq	#PATH_MASK,d1
	and.w	d0,d1
	lsl.w	#2,d1
	lea	EntryPaths(pc),a1
	add.w	d1,a1
	move.w	2(a1),d2
	add.w	d2,d2
	moveq	#0,d5
	btst	#CTLB_MIRROR,d0
	beq	.Plain
	moveq	#1,d5
	addq.w	#1,d2
.Plain	move.w	(a1),d0				; the script
	move.w	d2,d1
	add.w	d2,d2
	add.w	d1,d2				; 3 bytes a position
	lea	StartPos(pc),a1
	add.w	d2,a1
	moveq	#0,d1
	move.b	(a1)+,d1
	moveq	#0,d2
	move.b	(a1)+,d2
	move.b	(a1)+,d3
	bsr	FlightLaunch
	; its first chance to bomb comes sooner from the top than from the sides
	moveq	#ENTRY_WAIT,d0
	btst	#0,d7
	beq	.Top
	moveq	#SIDE_WAIT,d0
.Top	move.b	d0,fl_wait(a0)
	; may it bomb on its way in? The arcade's table has a bit per enemy, the first in bit 7
	move.w	d4,d0
	subq.w	#FIRST_ENEMY,d0
	lsr.w	#1,d0
	move.w	d0,d1
	lsr.w	#3,d1
	lea	EntryBombers(pc),a1
	move.b	(a1,d1.w),d1
	and.w	#7,d0
	lsl.b	d0,d1
	bpl	.Quiet
	move.b	EntryBombs(a5),fl_chances(a0)
.Quiet	moveq	#1,d0
	rts
