; Dives: which enemy leaves the formation to attack, and when.
;
; A port of the arcade's attack manager; the model is motion/dives.py.
; Every 16 arcade frames three timers count down: bosses, butterflies,
; bees. One that reaches zero sends an enemy of its kind, unless as many
; as the stage allows are flying already, and restarts from a value that
; depends on the stage, how many enemies are left and how long the stage
; has lasted.
;
; A bee or butterfly: the first one, in object order, that is in its place.
; A boss: every other time, if no boss is out capturing, the first boss in
; its place sets off alone to capture the fighter. Otherwise a boss goes
; with two of the three butterflies under it, or failing that with one, or
; alone. They are queued and leave on successive frames.
;
; A dive starts where the enemy is in the formation, heading up, and flies
; its kind's script, mirrored for enemies on the right.
;
; Attacks stop while the fighter is out of play.
;
; A capture attempt's tractor beam and what follows are in capture.s.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	DivesInit
	xdef	DivesTick
	xdef	InPlace
	xdef	DiveLaunch
	xref	FlightLaunch
	xref	HomeRc
	xref	DiveScripts
	xref	StageConfig
	xref	BombFlagTable
	xref	BossReload
	xref	ButterflyReload
	xref	BeeReload

; the stage's settings, a nibble each in the ROM's table
PARM_BOMBS	equ	0			; row of BombFlagTable
PARM_BOSS	equ	1			; row of BossReload
PARM_BUTTERFLY	equ	2			; row of ButterflyReload
PARM_BEE	equ	3			; row of BeeReload
PARM_MAX	equ	4			; how many may fly at once
PARM_MAX_LATER	equ	5			;   and from half way through the stage's time
PARM_LAST	equ	7			; with fewer enemies left than this they attack without pause
PARM_HARD	equ	8			; entry paths take their harder branch
PARM_HARDER	equ	9			; dives take their harder branch
CONFIG_STAGES	equ	26			; a rank's table has this many stages
CONFIG_BYTES	equ	5
CONFIG_REPEAT	equ	4			; stages past the table repeat its last four

STAGE_TIME	equ	120			; StageTime at the start of a stage
TIME_FRAMES	equ	32			; arcade frames per count
TIME_EARLY	equ	60			; below this, more may fly
TIME_MID	equ	40			; below this, and at 0, the timers restart lower
DIVE_FRAMES	equ	16			; arcade frames per count of the dive timers
LAST_RELOAD	equ	2			; every timer's restart value when few are left
TEN		equ	10
FIRST_WAVE_GAP	equ	2			; WaveTimer at the start of a stage
WAVE_SIZE	equ	8
CHALLENGE_MASK	equ	3			; a stage whose number ends in these two bits set is a challenging stage

; index of each kind's timer, and of its script in DiveScripts
KIND_OF_BOSS	equ	0
SCRIPT_BEE	equ	0
SCRIPT_BUTTERFLY equ	2
SCRIPT_BOSS	equ	4
SCRIPT_ROGUE	equ	6
SCRIPT_CAPTURE	equ	8

FIRST_BEE	equ	$08
BEES		equ	20
FIRST_BUTTERFLY	equ	$40
BUTTERFLIES	equ	16
BOSSES		equ	4
ESCORTS		equ	6
FIGHTER_MASK	equ	7			; a boss's captured fighter is the boss's object and this
RIGHT_SIDE	equ	1			; an object with this bit set is on the right: it flies mirrored
DQB_MIRROR	equ	7
FIRST_QUARTER	equ	1			; a dive starts heading up
DIVE_TOP	equ	352			; a dive starts at y = this - the enemy's y in HomeX

	section	code,code

;--
; DivesInit
; Set the dive logic up for a stage. Stage(a5) is set.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0-a1
DivesInit:
	; the stage's row of settings: stages past the table repeat its last four
	move.w	Stage(a5),d0
.Wrap	cmp.w	#CONFIG_STAGES+1,d0
	bcs	.Known
	subq.w	#CONFIG_REPEAT,d0
	bra	.Wrap
.Known	subq.w	#1,d0
	mulu.w	#CONFIG_BYTES,d0
	moveq	#0,d1
	move.b	Rank(a5),d1
	mulu.w	#CONFIG_STAGES*CONFIG_BYTES,d1
	lea	StageConfig(pc),a0
	add.w	d1,a0
	add.w	d0,a0
	lea	StageParms(a5),a1
	moveq	#CONFIG_BYTES-1,d0
.Parm	move.b	(a0)+,d1
	move.b	d1,d2
	lsr.b	#4,d2
	move.b	d2,(a1)+
	and.b	#15,d1
	move.b	d1,(a1)+
	dbf	d0,.Parm
	move.b	StageParms+PARM_MAX(a5),MaxFlying(a5)
	move.b	StageParms+PARM_HARD(a5),StageHard(a5)
	move.b	StageParms+PARM_HARDER(a5),StageHarder(a5)
	move.b	#STAGE_TIME,StageTime(a5)
	clr.b	Alive(a5)
	clr.b	FlyingHits(a5)
	move.b	#FIRST_WAVE_GAP,WaveTimer(a5)
	; a challenging stage's first wave counts for its bonus from the start
	clr.b	WaveHits(a5)
	moveq	#CHALLENGE_MASK,d0
	and.w	Stage(a5),d0
	subq.w	#CHALLENGE_MASK,d0
	bne	.Counted
	move.b	#WAVE_SIZE,WaveHits(a5)
.Counted
	clr.b	BossToggle(a5)
	clr.l	BossBonus(a5)			; a boss shot on its way in scores as one diving alone
	if	CAPTURE=0
	st	Capturing(a5)			; no boss tries to capture
	endc
	st	Special(a5)			; nobody is about to transform
	clr.b	FormDirty(a5)
	lea	DiveTimers(a5),a0
	move.b	#22,(a0)+			; the arcade's first timers: a boss after 22 counts,
	move.b	#2,(a0)+			; a butterfly and a bee after 2
	move.b	#2,(a0)+
	lea	DiveQueue(a5),a0
	moveq	#DIVE_QUEUE-1,d0
.Queue	move.b	#QUEUE_EMPTY,dq_obj(a0)
	addq.l	#dq_SIZEOF,a0
	dbf	d0,.Queue
	rts

;--
; DivesTick
; One arcade frame of the attack manager: keep the stage's clock and limits, and send the next diver.
; In:       d6.w = when in this displayed frame the arcade frame begins, in fifths,
;           a5 = state
; Out:      -
; Clobbers: d0-d5, d7, a0-a3
DivesTick:
	moveq	#TIME_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Timed
	tst.b	StageTime(a5)
	beq	.Timed
	subq.b	#1,StageTime(a5)
.Timed	; few enough left, and the fighter in play: they attack without pause. Without the
	; fighter they go home, which is what lets the next one come on.
	move.b	Alive(a5),d0
	cmp.b	StageParms+PARM_LAST(a5),d0
	scs	d1
	and.b	InPlay(a5),d1
	sne	d1
	neg.b	d1
	move.b	d1,LastStand(a5)

	; the limits and restart values for the state of the stage
	move.b	StageTime(a5),d2
	cmp.b	#TIME_EARLY,d2
	bcc	.Early
	move.b	StageParms+PARM_MAX_LATER(a5),MaxFlying(a5)
.Early	moveq	#0,d0
	move.b	Alive(a5),d0
	divu.w	#TEN,d0				; d0.w = enemies left / 10
	lea	StageParms(a5),a1
	lea	DiveReload(a5),a2
	moveq	#0,d3
	move.b	PARM_BOMBS(a1),d3
	lsl.w	#2,d3
	add.w	d0,d3
	lea	BombFlagTable(pc),a0
	move.b	(a0,d3.w),BombFlags(a5)
	tst.b	d1
	beq	.Paced
	moveq	#LAST_RELOAD,d3
	move.b	d3,(a2)+
	move.b	d3,(a2)+
	move.b	d3,(a2)
	if	SOUND_TEST=0
	clr.b	Sound+SND_PULSE(a5)		; and the formation's pulse stops
	endc
	bra	.Send
.Paced	moveq	#0,d3
	move.b	PARM_BOSS(a1),d3
	lsl.w	#2,d3
	add.w	d0,d3
	lea	BossReload(pc),a0
	move.b	(a0,d3.w),(a2)+
	; late = 0, 1 below TIME_MID, 2 when the time is up
	moveq	#0,d0
	cmp.b	#TIME_MID,d2
	bcc	.Late
	moveq	#1,d0
	tst.b	d2
	bne	.Late
	moveq	#2,d0
.Late	moveq	#0,d3
	move.b	PARM_BUTTERFLY(a1),d3
	move.w	d3,d1
	add.w	d3,d3
	add.w	d1,d3
	add.w	d0,d3
	lea	ButterflyReload(pc),a0
	move.b	(a0,d3.w),(a2)+
	moveq	#0,d3
	move.b	PARM_BEE(a1),d3
	move.w	d3,d1
	add.w	d3,d3
	add.w	d1,d3
	add.w	d0,d3
	lea	BeeReload(pc),a0
	move.b	(a0,d3.w),(a2)

	; nobody dives until every wave is in, or while the fighter is out of play
.Send	tst.b	WavesIn(a5)
	beq	.Done
	tst.b	InPlay(a5)
	beq	.Done
	tst.b	RescueOn(a5)			; nor while a rescued fighter is on its way down
	bne	.Done
	; someone queued leaves first
	lea	DiveQueue(a5),a2
	moveq	#DIVE_QUEUE-1,d2
.Queued	moveq	#0,d4
	move.b	dq_obj(a2),d4
	cmp.b	#QUEUE_EMPTY,d4
	bne	.Leave
	addq.l	#dq_SIZEOF,a2
	dbf	d2,.Queued
	moveq	#DIVE_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Done
	lea	DiveTimers(a5),a0
	moveq	#0,d3
.Timer	subq.b	#1,(a0)
	beq	.Due
	addq.l	#1,a0
	addq.w	#1,d3
	cmp.w	#DIVE_KINDS,d3
	bne	.Timer
.Done	rts
.Due	move.b	Flying+1(a5),d0
	cmp.b	MaxFlying(a5),d0
	bcs	.Go
	addq.b	#1,(a0)				; enough are flying: try again next time
	rts
.Go	move.b	DIVE_KINDS(a0),(a0)		; its restart value
	tst.w	d3
	beq	Boss
	moveq	#FIRST_BUTTERFLY,d4
	moveq	#BUTTERFLIES-1,d2
	move.w	DiveScripts+SCRIPT_BUTTERFLY(pc),a3
	subq.w	#1,d3
	beq	.First
	moveq	#FIRST_BEE,d4
	moveq	#BEES-1,d2
	move.w	DiveScripts+SCRIPT_BEE(pc),a3
	; the first of its kind that is in its place
.First	cmp.b	Special(a5),d4
	beq	.Next
	bsr	InPlace
	bne	.Found
.Next	addq.w	#2,d4
	dbf	d2,.First
	rts
.Found	btst	#RIGHT_SIDE,d4
	sne	d5
	move.w	a3,d0
	bra	DiveLaunch

.Leave	move.b	#QUEUE_EMPTY,dq_obj(a2)
	bclr	#DQB_MIRROR,d4
	sne	d5
	bsr	InPlace
	beq	.Done
	move.w	dq_script(a2),d0
	bra	DiveLaunch

;--
; Boss
; A boss's turn to dive: choose the boss and who goes with it, and queue them.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, d7, a0-a3
Boss:	tst.b	Capturing(a5)
	bne	.Escorted
	addq.b	#1,BossToggle(a5)
	btst	#0,BossToggle(a5)
	bne	.Escorted
	; a capture attempt: the first boss in its place, alone
	lea	BossOrder(pc),a1
	moveq	#BOSSES-1,d2
.Captor	moveq	#0,d4
	move.b	(a1)+,d4
	bsr	InPlace
	bne	.Capture
	dbf	d2,.Captor
	rts
.Capture
	st	Capturing(a5)
	move.b	d4,CaptureBoss(a5)
	move.w	DiveScripts+SCRIPT_CAPTURE(pc),a3
	moveq	#0,d3
	moveq	#0,d5
	moveq	#0,d2
	bra	.Queue

	; d7 = bit n set if escort n is in its place: the six butterflies under the bosses, right to left
.Escorted
	lea	Escorts(pc),a1
	move.w	DiveScripts+SCRIPT_BOSS(pc),a3
	moveq	#0,d7
	moveq	#0,d2
.There	moveq	#0,d4
	move.b	(a1,d2.w),d4
	cmp.b	Special(a5),d4
	beq	.Absent
	bsr	InPlace
	beq	.Absent
	bset	d2,d7
.Absent	addq.w	#1,d2
	cmp.w	#ESCORTS,d2
	bne	.There
	; first a boss with two of its three escorts there, then one with one;
	; boss n (4 is the leftmost) has escorts n+1, n and n-1
	moveq	#2,d3
.Want	moveq	#BOSSES,d2
.Try	move.w	d7,d5
	move.w	d2,d0
	subq.w	#1,d0
	lsr.w	d0,d5
	and.w	#7,d5				; its three escorts: bit 2 is the leftmost
	lea	BitCount(pc),a0
	move.b	(a0,d5.w),d0
	cmp.b	d3,d0
	bcs	.Other
	lea	BossOf-1(pc),a0
	moveq	#0,d4
	move.b	(a0,d2.w),d4
	bsr	InPlace
	beq	.Other
	subq.w	#1,d2				; its rightmost escort's number
	bra	.Queue
.Other	subq.w	#1,d2
	bne	.Try
	subq.w	#1,d3
	bne	.Want
	; no escorts anywhere: the first boss in its place, alone
	lea	BossOrder(pc),a1
	moveq	#BOSSES-1,d2
.Alone	moveq	#0,d4
	move.b	(a1)+,d4
	bsr	InPlace
	bne	.Solo
	dbf	d2,.Alone
	; no boss either: a captured fighter whose boss is gone
	move.w	DiveScripts+SCRIPT_ROGUE(pc),a3
	moveq	#0,d4
.Rogue	bsr	InPlace
	bne	.Fighter
	addq.w	#2,d4
	cmp.w	#2*BOSSES,d4
	bne	.Rogue
	rts
.Fighter
	move.w	d4,d7
	lea	DiveQueue(a5),a2
	bra	Enqueue
.Solo	moveq	#0,d3
	moveq	#0,d5
	moveq	#0,d2

	; d4 = who leads, a3 = script, d5 = its escorts' bits, d3 = how many of them go,
	; d2 = its rightmost escort's number
.Queue	move.w	d4,d7				; the leader, kept for its side and its fighter
	; a boss shot while diving scores by how many set off with it
	moveq	#FIGHTER_MASK,d0
	and.w	d4,d0
	lsr.w	#1,d0
	lea	BossBonus(a5),a0
	move.b	d3,(a0,d0.w)
	lea	DiveQueue(a5),a2
	bsr	Enqueue
	lea	Escorts+2(pc),a1
	add.w	d2,a1				; the leftmost escort
	rept	3
	bsr	Escort
	endr
	; a captured fighter parked above the boss goes along
	moveq	#FIGHTER_MASK,d4
	and.w	d7,d4
	bsr	InPlace
	beq	.Queued
	bsr	Enqueue
.Queued	rts

; how many of three bits are set
BitCount:
	dc.b	0,1,1,2,1,2,2,3
; boss 1 to 4, right to left
BossOf:	dc.b	$32,$36,$34,$30
; the bosses in object order
BossOrder:
	dc.b	$30,$32,$34,$36
; the butterflies under the bosses, right to left
Escorts:
	dc.b	$4a,$52,$5a,$58,$50,$48

;--
; Escort
; Queue the next escort to the left if it is there and one is still wanted.
; In:       a1 = its entry in Escorts, a2 = the queue entry to fill, a3 = script,
;           d3.w = escorts still wanted, d5 = bit 2 set if this one is there, d7 = the leader
; Out:      a1 = the entry of the next escort to the right, a2 = the next queue entry,
;           d3.w = escorts still wanted, d5 = bit 2 set if the next one is there
; Clobbers: d4
Escort:	btst	#2,d5
	beq	.Skip
	tst.w	d3
	beq	.Skip
	subq.w	#1,d3
	moveq	#0,d4
	move.b	(a1),d4
	bsr	Enqueue
.Skip	add.w	d5,d5
	subq.l	#1,a1
	rts

;--
; Enqueue
; Put an enemy in the dive queue, on the leader's side.
; In:       a2 = the queue entry to fill, d4.b = object, a3 = script, d7 = the leader
; Out:      a2 = the next queue entry
; Clobbers: -
Enqueue:
	move.b	d4,dq_obj(a2)
	btst	#RIGHT_SIDE,d7
	beq	.Left
	bset	#DQB_MIRROR,dq_obj(a2)
.Left	move.w	a3,dq_script(a2)
	addq.l	#dq_SIZEOF,a2
	rts

;--
; InPlace
; Is an enemy in its place in the formation?
; In:       d4.w = object, a5 = state
; Out:      Z = no
; Clobbers: d0-d1, a0
InPlace:
	lea	HomeRc(pc),a0
	moveq	#0,d0
	move.b	(a0,d4.w),d0
	moveq	#0,d1
	move.b	1(a0,d4.w),d1
	lsr.w	#1,d1				; its column
	sub.w	#HOME_ROWS+2*STRIP_ROWS,d0	; its row, doubled
	bcs	.Captive
	lea	FormPresent(a5),a0
	move.w	(a0,d0.w),d0
	btst	d1,d0
	rts
	; a captured fighter's place: is the one there is in it?
.Captive
	cmp.b	#CS_PLACED,CaptiveState(a5)
	bne	.No
	cmp.b	CaptiveObj(a5),d4
	bne	.No
	moveq	#1,d0
	rts
.No	moveq	#0,d0
	rts

;--
; DiveLaunch
; Take an enemy out of the formation and start its dive, if there is a free flight.
; In:       d4.w = object, d0.w = script, d5.b = nonzero to fly it mirrored,
;           d6.w = when in this displayed frame the arcade frame begins, in fifths,
;           a5 = state
; Out:      -
; Clobbers: d0-d3, a0-a1
DiveLaunch:
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d1
.Slot	moveq	#1<<FLB_ACTIVE|1<<FLB_LANDED,d2
	and.b	fl_flags(a0),d2
	beq	.Free
	lea	fl_SIZEOF(a0),a0
	dbf	d1,.Slot
	rts
.Free	moveq	#0,d1
	moveq	#0,d2
	moveq	#FIRST_QUARTER,d3
	bsr	FlightLaunch
	move.b	#DIVE_WAIT,fl_wait(a0)		; a diver's chances to bomb are the stage's, as it stands
	move.b	BombFlags(a5),fl_chances(a0)
	LOG	#STAGE_LAUNCHED,d4
	; it starts where it is: x = HomeX[column], y = 352 - HomeX[row], in pixels
	lea	HomeRc(pc),a1
	moveq	#0,d2
	move.b	(a1,d4.w),d2			; row entry
	moveq	#0,d3
	move.b	1(a1,d4.w),d3			; column entry
	lea	HomeX(a5),a1
	moveq	#0,d0
	move.b	(a1,d3.w),d0
	lsl.w	#7,d0
	move.w	d0,fl_x(a0)
	moveq	#0,d0
	move.b	(a1,d2.w),d0
	neg.w	d0
	add.w	#DIVE_TOP,d0
	lsl.w	#7,d0
	move.w	d0,fl_y(a0)
	; and is gone from its row, whose strip must be rebuilt at once
	lsr.w	#1,d3
	sub.w	#HOME_ROWS+2*STRIP_ROWS,d2
	bcc	.Row
	move.b	#CS_FLYING,CaptiveState(a5)	; the captured fighter leaves its place
	bra	.Sound
.Row
	lea	FormPresent(a5),a1
	move.w	(a1,d2.w),d0
	bclr	d3,d0
	move.w	d0,(a1,d2.w)
	lsr.w	#1,d2
	bset	d2,FormDirty(a5)
.Sound
	if	SOUND_TEST=0			; the sound test makes its own requests
	move.b	#1,Sound+SND_DIVE(a5)
	endc
	rts
