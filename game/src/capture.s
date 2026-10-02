; Capture: the boss's tractor beam and the fighter it takes.
;
; Ported from the arcade's four tasks for it (main CPU $21CB, $2222, $20F2
; and $19B2), with their counters and timings.
;
;   Approach: a boss on a capture dive stops over where the fighter was,
;     turns until it points straight down, and puts the beam out.
;   Beam: it grows a row every few arcade frames to 10 rows, is held for 64
;     frames, and goes back in. Only while it is held does it take a fighter
;     that is under it. A boss shot meanwhile loses its beam quickly.
;   Pull: the fighter spins and is drawn up and towards the boss, a line a
;     frame. Near the top it turns red and is the boss's.
;   Carry: FIGHTER CAPTURED and its tune; the boss flies home with the
;     fighter under it, the fighter moves up into its place above the boss,
;     and the player goes on with the next fighter, if there is one.
;   Rescue ($2000): the boss shot while it dives with its captured fighter
;     sets the fighter free. It spins until nothing is flying, comes to the
;     middle and down, and joins the player's fighter, which has moved over:
;     two fighters side by side. If the player's fighter was lost meanwhile,
;     the rescued one takes its place.
;
; The beam is the arcade's 48 x 80 image in its three colour sets, copied to
; the screen each frame while it shows, as much of it as is out.
;
; Not built yet: shooting from inside the beam (the arcade lets the spinning
; fighter fire the way it points), and a captured fighter that has flown off
; alone coming back with the next stage's bosses.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	CaptureInit
	xdef	CaptureTick
	xdef	BeamDraw
	xdef	RescueStart
	xref	FlightTurn
	xref	FlightPlace
	xref	TextShow
	xref	TextHide
	xref	DiveScripts
	xref	Beam

TIMER_FRAMES	equ	32			; arcade frames per count of CapTimer
TURN_RATE	equ	12			; the hovering boss turns this fast until it points down
UPRIGHT_MIN	equ	$78			; pointing straight up or down: heading / 2, less this,
UPRIGHT_RANGE	equ	$10			;   is below this
PARM_BEAM	equ	6			; the stage's setting for the beam's frames per step
FAST_BEAM	equ	3			; frames per step when the boss has been shot
PULL_BEAM	equ	10			;   and once it has the fighter
BEAM_ROWS	equ	10
BEAM_END	equ	BEAM_ROWS+1		; the step after the last row
STEP_MASK	equ	15
BSB_SHOT	equ	7			; BeamStep bits: the boss was shot,
BSB_IN		equ	6			;   the beam is going back in,
BSB_LAST	equ	5			;   and has waited for the fighter to arrive
BEAM_HELD	equ	1<<BSB_IN		; BeamStep and BeamWait while the beam is fully out
BEAM_TAKING	equ	1<<BSB_IN|1<<BSB_LAST|8	; BeamStep for the last few steps once it has the fighter
REACH		equ	$1b			; the held beam takes a fighter within this many pixels of its centre
HOLD_FIFTHS	equ	255*FRAME_FIFTHS	; the boss's step while the beam is out
RELEASE_FIFTHS	equ	FRAME_FIFTHS		;   and when it lets go: it moves on next frame
CARRY_FIFTHS	equ	4*FRAME_FIFTHS		;   and while the text shows
FIRE_OFF_Y	equ	$e6			; the pulled fighter's y (low byte) from where it cannot get away,
TAKEN_Y		equ	$e0			;   and where it is the boss's
TEXT_COUNTS	equ	6			; counts FIGHTER CAPTURED shows
TUNE_COUNT	equ	4			; the count at which its tune starts
CARRY_BELOW	equ	16			; the carried fighter is this far below its boss
JOIN_LINES	equ	$24			; lines it then moves up into its place
LOST_PAUSE	equ	4			; counts until the next fighter is due, as after an explosion
WINGS_CLOSED	equ	7			; the fighter's frame when captured
UPRIGHT		equ	6
SCRIPT_AFTER	equ	10			; in DiveScripts: the boss flies home with the fighter
NO_BOSS		equ	1			; CaptureBoss when no boss is capturing
TEXT_COLUMN	equ	6
TEXT_ROW	equ	17
TEXT_LINE	equ	1
; the beam's image and where it goes
BEAM_WORDS	equ	3
BEAM_LINE	equ	BEAM_WORDS*2*PLANES	; bytes in one line of it
BEAM_SET	equ	BEAM_ROWS*8*BEAM_LINE	; bytes in one colour set
BEAM_Y		equ	GUARD+168		; its top in buffer rows: just under the hovering boss
BEAM_LEFT	equ	33-GUARD		; from the boss's sprite x to the beam's left edge in the buffer
BLIT_WORDS	equ	BEAM_WORDS+1		; a word more for the shift
ROW_SIZE_SHIFT	equ	11			; a row of the beam in bltsize: 8 lines of 4 planes, in the height's place
CLEAR		equ	$0100			; bltcon0: D only, all zeros
COPY		equ	$09f0			; bltcon0: D = A
FIRST_WORDS	equ	$ffff0000		; bltafwm:bltalwm: all but the extra word
FIRST_ENEMY	equ	$08			; objects below this are captured fighters
SPIN_COUNTS	equ	2			; a rescued fighter spins for at least this many counts
DOCK_SX		equ	$80			; it comes down here,
DOCK_LEFT_SX	equ	$71			;   and the player's fighter waits here, to its left
SY_MASK		equ	$1ff			; the arcade's sprite y has 9 bits
RS_SPIN		equ	1			; RescueStep
RS_LAND		equ	2
RS_DOWN		equ	3

	section	code,code

;--
; CaptureInit
; A new game: nothing captured, no beam.
; In:       a5 = state
; Out:      -
; Clobbers: -
CaptureInit:
	clr.b	ApproachOn(a5)
	clr.b	BeamOn(a5)
	; none of the beam shows: whoever has its place cleared after this (BeamWipe) would
	; otherwise have the rows that were out drawn there again, into screens just cleared
	clr.b	BeamTop(a5)
	clr.b	BeamBottom(a5)
	clr.b	PullOn(a5)
	clr.b	CarryOn(a5)
	clr.b	CapText(a5)
	clr.b	BeamWipe(a5)
	clr.b	StarBack(a5)
	clr.b	CaptiveState(a5)
	clr.b	CaptiveWhite(a5)
	clr.b	RescueOn(a5)
	if	DUAL_START
	st	Capturing(a5)			; as after a rescue: no boss tries to capture two
	else
	clr.b	Capturing(a5)
	endc
	move.b	#NO_BOSS,CaptureBoss(a5)
	if	SOUND_TEST=0
	clr.b	Sound+SND_RESCUED(a5)
	clr.b	Sound+SND_BEAM(a5)
	clr.b	Sound+SND_BEAM_CAPTURE(a5)
	clr.b	Sound+SND_CAPTURED(a5)
	endc
	rts

;--
; CaptureTick
; One arcade frame of whatever part of a capture is going on.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
CaptureTick:
	moveq	#TIMER_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Timed
	tst.b	CapTimer(a5)
	beq	.Timed
	subq.b	#1,CapTimer(a5)
.Timed	tst.b	ApproachOn(a5)
	beq	.Beam
	bsr	Approach
.Beam	tst.b	BeamOn(a5)
	beq	.Pull
	bsr	BeamStepper
.Pull	tst.b	PullOn(a5)
	beq	.Carry
	bsr	Pull
.Carry	tst.b	CarryOn(a5)
	beq	.Rescue
	bsr	Carry
.Rescue	tst.b	RescueOn(a5)
	bne	Rescue
	rts

;--
; BossFlying
; Is the capturing boss still in flight?
; In:       a5 = state
; Out:      a0 = its flight, Z = no
; Clobbers: d0
BossFlying:
	move.l	CaptureSlot(a5),a0
	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.No
	move.b	fl_obj(a0),d0
	cmp.b	CaptureBoss(a5),d0
	seq	d0
	tst.b	d0
.No	rts

;--
; Approach
; The boss on its way down: once it has stopped it turns to point down, then the beam starts.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0, a2
Approach:
	bsr	BossFlying
	bne	.There
	clr.b	ApproachOn(a5)			; shot on the way: another boss may try
	clr.b	Capturing(a5)
	rts
.There	tst.b	fl_lo(a0)
	bne	.Done				; still coming down
	moveq	#TURN_RATE,d0
	btst	#6,fl_head(a0)			; in the second half of a half turn: the other way round
	beq	.Turn
	neg.b	d0
.Turn	bsr	FlightTurn
	; pointing straight up or down? The arcade halves a 9-bit heading and takes a 16-wide window
	move.w	fl_head(a0),d0
	lsr.w	#7,d0
	sub.b	#UPRIGHT_MIN,d0
	cmp.b	#UPRIGHT_RANGE,d0
	bcc	.Done
	moveq	#0,d0
	bsr	FlightTurn
	move.b	StageParms+PARM_BEAM(a5),BeamFrames(a5)
	clr.b	ApproachOn(a5)
	clr.b	BeamStep(a5)
	clr.b	Connected(a5)
	clr.b	FireOff(a5)
	clr.b	BeamTop(a5)
	clr.b	BeamBottom(a5)
	st	BeamOn(a5)
	move.b	#1,BeamWait(a5)
	st	Pulling(a5)
	moveq	#0,d0
	move.b	BeamColumn(a5),d0
	sub.w	#BEAM_LEFT,d0
	move.w	d0,BeamX(a5)
.Done	rts

;--
; BeamStepper
; One arcade frame of the beam.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0
BeamStepper:
	btst	#BSB_SHOT,BeamStep(a5)
	bne	.Count
	bsr	BossFlying
	bne	.Count
	; the boss has been shot: the beam goes, quickly
	move.b	#FAST_BEAM,BeamFrames(a5)
	move.b	#1<<BSB_SHOT,BeamStep(a5)
	clr.b	Pulling(a5)
	clr.b	StarBack(a5)
	move.b	#1,BeamWait(a5)
	rts
.Count	subq.b	#1,BeamWait(a5)
	beq	.Step
	; between steps: while the beam is held, a fighter under it is taken
	cmp.b	#BEAM_HELD,BeamStep(a5)
	bne	.Done
	cmp.b	#PS_PLAYING,PlayerState(a5)
	bne	.Done
	move.b	BeamColumn(a5),d0
	move.w	ShipX(a5),d1
	add.w	#DISPLAY_SX,d1
	sub.b	d1,d0
	add.b	#REACH,d0
	cmp.b	#2*REACH,d0
	bcc	.Done
	move.b	#PS_TAKEN,PlayerState(a5)
	clr.b	InPlay(a5)
	clr.b	FirePending(a5)
	st	PullOn(a5)
	st	StarBack(a5)
	move.b	#PULL_BEAM,BeamFrames(a5)
	if	SOUND_TEST=0
	clr.b	Sound+SND_BEAM(a5)
	move.b	#1,Sound+SND_BEAM_CAPTURE(a5)
	endc
.Done	rts

.Step	move.b	BeamFrames(a5),BeamWait(a5)
	btst	#BSB_SHOT,BeamStep(a5)
	beq	.Whole
	; a shot boss's beam goes from the top down
	addq.b	#1,BeamStep(a5)
	moveq	#STEP_MASK,d0
	and.b	BeamStep(a5),d0
	cmp.b	#BEAM_END,d0
	beq	.Gone
	move.b	d0,BeamTop(a5)
	rts
.Gone	clr.b	Capturing(a5)
	bra	.Off

.Whole	if	SOUND_TEST=0
	tst.b	PullOn(a5)
	bne	.Hold
	move.b	#1,Sound+SND_BEAM(a5)
	endc
.Hold	bsr	BossFlying			; the boss stays where it is
	beq	.Next
	move.w	#HOLD_FIFTHS,fl_left(a0)
.Next	addq.b	#1,BeamStep(a5)
	moveq	#STEP_MASK,d0
	and.b	BeamStep(a5),d0
	cmp.b	#BEAM_END,d0
	beq	.Limit
	btst	#BSB_IN,BeamStep(a5)
	bne	.In
	move.b	d0,BeamBottom(a5)		; one more row out
	rts
.In	neg.b	d0				; one row fewer, from the bottom
	add.b	#BEAM_ROWS,d0
	move.b	d0,BeamBottom(a5)
	rts
.Limit	btst	#BSB_IN,BeamStep(a5)
	bne	.Back
	move.b	#BEAM_HELD,BeamStep(a5)		; fully out: held for 64 frames
	move.b	#BEAM_HELD,BeamWait(a5)
	rts
	; fully in. If it has a fighter that has not arrived yet, it waits a few steps more.
.Back	tst.b	Connected(a5)
	beq	.Empty
	btst	#BSB_LAST,BeamStep(a5)
	bne	.Took
	move.b	#BEAM_TAKING,BeamStep(a5)
	rts
.Took	; the boss flies home with it
	bsr	BossFlying
	beq	.Lost
	move.w	DiveScripts+SCRIPT_AFTER(pc),fl_script(a0)
.Lost	clr.b	StarBack(a5)
	st	CarryOn(a5)
	st	CapText(a5)
	bra	.Off
	; nobody taken: the boss flies on, and another may try
.Empty	clr.b	Capturing(a5)
	move.b	#NO_BOSS,CaptureBoss(a5)
	bsr	BossFlying
	beq	.Off
	move.w	#RELEASE_FIFTHS,fl_left(a0)
.Off	clr.b	BeamOn(a5)
	clr.b	BeamTop(a5)
	clr.b	BeamBottom(a5)
	move.b	#2,BeamWipe(a5)			; its place is cleared in both screens
	if	SOUND_TEST=0
	clr.b	Sound+SND_BEAM(a5)
	clr.b	Sound+SND_BEAM_CAPTURE(a5)
	endc
	rts

;--
; Pull
; One arcade frame of the fighter in the beam: it spins, and goes up, or back down if let go.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0
Pull:	lea	ShipCode(a5),a0
	move.b	Pulling(a5),d0
	bsr	Spin
	tst.b	d0
	beq	.Turning
	; upright, and not being pulled any more
	tst.b	FireOff(a5)
	beq	.Back
	btst	#BSB_SHOT,BeamStep(a5)
	bne	.Back				; taken, but the boss was shot in time
	st	Connected(a5)
	clr.b	PullOn(a5)
	rts
.Turning
	btst	#BSB_SHOT,BeamStep(a5)
	bne	.Back
	tst.b	Pulling(a5)
	beq	.Done
	; a pixel towards the boss's column, a line up
	move.w	ShipX(a5),d1
	add.w	#DISPLAY_SX,d1
	moveq	#0,d2
	move.b	BeamColumn(a5),d2
	cmp.w	d2,d1
	beq	.Up
	bcs	.Right
	subq.w	#2,ShipX(a5)
.Right	addq.w	#1,ShipX(a5)
.Up	subq.w	#1,ShipSY(a5)
	move.b	ShipSY+1(a5),d1
	cmp.b	#FIRE_OFF_Y,d1
	bne	.Taken
	st	FireOff(a5)
.Taken	cmp.b	#TAKEN_Y,d1
	bne	.Done
	clr.b	Pulling(a5)
	; it is the boss's: from here it is drawn red, as the captured fighter
	st	ShipGone(a5)
	move.b	#CS_CARRIED,CaptiveState(a5)
.Done	bra	.Mirror
	; let go: back down a line a frame; once down and upright it is the player's again
.Back	cmp.w	#SHIP_SY,ShipSY(a5)
	beq	.Down
	addq.w	#1,ShipSY(a5)
	bra	.Mirror
.Down	tst.b	d0
	beq	.Mirror
	clr.b	PullOn(a5)
	clr.b	FireOff(a5)
	clr.b	ShipGone(a5)
	clr.b	CaptiveState(a5)
	move.b	#PS_PLAYING,PlayerState(a5)
	st	InPlay(a5)
	rts
	; while it is red the captured fighter's sprite shows it
.Mirror	tst.b	ShipGone(a5)
	beq	.Shown
	move.w	ShipX(a5),d1
	add.w	#DISPLAY_SX,d1
	move.w	d1,CaptiveX(a5)
	move.w	ShipSY(a5),CaptiveY(a5)
	move.b	ShipCode(a5),CaptiveCode(a5)
	move.b	ShipCtrl(a5),CaptiveCtrl(a5)
.Shown	rts

;--
; Spin
; Turn a fighter one step of its spin, unless it is upright and need not go on.
; In:       a0 = its frame, followed by its flip, d0.b = nonzero: it goes on spinning
; Out:      d0.b = nonzero if it is upright and has stopped
; Clobbers: d1-d2
Spin:	; c = which quarter of the turn the flips put it in: flips 0, 1, 3, 2 are quarters 0 to 3
	move.b	1(a0),d1
	move.b	d1,d2
	lsr.b	#1,d2
	eor.b	d2,d1
	move.b	(a0),d2
	cmp.b	#UPRIGHT,d2
	bne	.Go
	tst.b	d1
	bne	.Go
	tst.b	d0
	bne	.Go
	moveq	#1,d0
	rts
	; in even quarters the frame counts up to 6, in odd ones down to 0; at the end, the
	; quarter before
.Go	btst	#0,d1
	bne	.Odd
	cmp.b	#UPRIGHT,d2
	beq	.Quarter
	addq.b	#1,d2
	bra	.Set
.Odd	tst.b	d2
	beq	.Quarter
	subq.b	#1,d2
	bra	.Set
.Quarter
	subq.b	#1,d1
	and.b	#3,d1
	bra	.Go
.Set	move.b	d2,(a0)
	btst	#1,d1
	beq	.Flips
	eor.b	#1,d1
.Flips	move.b	d1,1(a0)
	moveq	#0,d0
	rts

;--
; Carry
; One arcade frame of the boss taking the fighter home.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
Carry:	tst.b	CapText(a5)
	beq	.Shown
	; FIGHTER CAPTURED; the fighter is now the boss's captive, where the fighter was
	clr.b	CapText(a5)
	clr.b	JoinCount(a5)
	move.b	#TEXT_COUNTS,CapTimer(a5)
	moveq	#7,d0
	and.b	CaptureBoss(a5),d0
	move.b	d0,CaptiveObj(a5)
	move.b	#CS_CARRIED,CaptiveState(a5)
	move.b	#WINGS_CLOSED,CaptiveCode(a5)
	clr.b	CaptiveCtrl(a5)
	lea	CapturedText(pc),a0
	moveq	#TEXT_COLUMN,d1
	moveq	#TEXT_ROW,d2
	moveq	#TEXT_RED,d3
	moveq	#TEXT_LINE,d0
	bra	TextShow
.Shown	tst.b	CapTimer(a5)
	beq	.Home
	cmp.b	#TUNE_COUNT,CapTimer(a5)
	bne	.Wait
	subq.b	#1,CapTimer(a5)
	SOUND	SND_CAPTURED
.Wait	bsr	BossFlying			; the boss waits while the text shows
	beq	.Done
	move.w	#CARRY_FIFTHS,fl_left(a0)
.Done	rts
.Home	moveq	#TEXT_LINE,d0
	bsr	TextHide
	bsr	BossFlying
	beq	.Join
	; under the boss as it flies home
	bsr	FlightPlace
	addq.w	#SPRITE_X,d0
	add.w	#SPRITE_Y+CARRY_BELOW,d1
	move.w	d0,CaptiveX(a5)
	move.w	d1,CaptiveY(a5)
	rts
	; the boss is home (or gone): the fighter moves up into its place above it
.Join	move.b	#UPRIGHT,CaptiveCode(a5)
	cmp.b	#JOIN_LINES,JoinCount(a5)
	beq	.Placed
	addq.b	#1,JoinCount(a5)
	subq.w	#1,CaptiveY(a5)
	rts
.Placed	clr.b	CarryOn(a5)
	if	SOUND_TEST=0
	clr.b	Sound+SND_CAPTURED(a5)
	endc
	move.b	#CS_PLACED,CaptiveState(a5)
	addq.b	#1,Alive(a5)			; it is one of the enemy now
	move.b	#NO_BOSS,CaptureBoss(a5)
	; and the player has lost a fighter: the next one is due as after an explosion
	move.b	#PS_BLOWN,PlayerState(a5)
	clr.b	FighterStep(a5)
	move.b	#LOST_PAUSE,GameTimer(a5)
	LOG	#STAGE_FIGHTER_LOST,Lives(a5)
	rts

;--
; RescueStart
; The boss flying with its captured fighter has been destroyed: the fighter is free.
; In:       a5 = state
; Out:      -
; Clobbers: -
RescueStart:
	movem.l	d0/a0,-(sp)
	lea	Flights(a5),a0			; it stops flying where it is
	moveq	#FLIGHT_SLOTS-1,d0
.Slot	cmp.b	#FIRST_ENEMY,fl_obj(a0)
	bcc	.Next
	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.Next
	clr.b	fl_flags(a0)
.Next	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Slot
	move.b	#CS_RESCUED,CaptiveState(a5)
	st	CaptiveWhite(a5)
	st	RescueOn(a5)
	clr.b	RescueStep(a5)
	subq.b	#1,Alive(a5)			; no longer one of the enemy
	SOUND	SND_RESCUED
	movem.l	(sp)+,d0/a0
	rts

;--
; Rescue
; One arcade frame of a freed fighter: spinning, then down to the player's fighter.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0
Rescue:	move.b	RescueStep(a5),d0
	bne	.Begun
	move.b	#RS_SPIN,RescueStep(a5)
	move.b	#SPIN_COUNTS,CapTimer(a5)
	rts
.Begun	subq.b	#RS_SPIN,d0
	bne	.Landing
	; it spins for its counts, and while anything is still flying
	move.b	CapTimer(a5),d0
	or.b	Flying+1(a5),d0
	lea	CaptiveCode(a5),a0
	bsr	Spin
	tst.b	d0
	beq	.Done
	st	Docking(a5)
	move.b	#RS_LAND,RescueStep(a5)
.Done	rts
	; to the middle, then down to the fighter's line; from below it, the arcade's
	; 9-bit y takes it round by the top
.Landing
	move.w	CaptiveX(a5),d0
	cmp.w	#DOCK_SX,d0
	beq	.Down
	bcs	.Right
	subq.w	#2,CaptiveX(a5)
.Right	addq.w	#1,CaptiveX(a5)
	bra	.Fighter
.Down	cmp.w	#SHIP_SY,CaptiveY(a5)
	bne	.Lower
	move.b	#RS_DOWN,RescueStep(a5)
	bra	.Fighter
.Lower	addq.w	#1,CaptiveY(a5)
	and.w	#SY_MASK,CaptiveY(a5)
	; the player's fighter makes room
.Fighter
	move.b	PlayerState(a5),d0
	beq	.Move				; PS_PLAYING
	subq.b	#PS_READY,d0
	bne	.Alone
.Move	move.w	ShipX(a5),d0
	cmp.w	#DOCK_LEFT_SX-DISPLAY_SX,d0
	beq	.Room
	bcs	.East
	subq.w	#2,ShipX(a5)
.East	addq.w	#1,ShipX(a5)
	rts
.Room	cmp.b	#RS_DOWN,RescueStep(a5)
	bne	.Done
	st	Dual(a5)			; side by side
	bra	.Joined
	; no fighter for it to join: it is the player's fighter now
.Alone	cmp.b	#RS_DOWN,RescueStep(a5)
	bne	.Done
	clr.b	Capturing(a5)
	move.w	#DOCK_SX-DISPLAY_SX,ShipX(a5)
	move.b	#PS_PLAYING,PlayerState(a5)
	st	InPlay(a5)
	clr.b	FighterStep(a5)
	clr.b	GameTimer(a5)
.Joined	clr.b	CaptiveState(a5)
	clr.b	CaptiveWhite(a5)
	clr.b	Docking(a5)
	clr.b	RescueOn(a5)
	clr.b	FirePending(a5)
	if	SOUND_TEST=0
	clr.b	Sound+SND_RESCUED(a5)
	endc
	rts

CapturedText:
	dc.b	"FIGHTER CAPTURED",0
	even

;--
; BeamDraw
; Draw the beam's place in the back screen in one pass: as much of the beam as is out, and
; blank above and below it. The copy needs no clear first, and a full beam is one blit.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d4, a0-a1
BeamDraw:
	tst.b	BeamOn(a5)
	bne	.Draw
	tst.b	BeamWipe(a5)
	beq	.None
	subq.b	#1,BeamWipe(a5)
.Draw	move.l	BackScreen(a5),a0
	move.l	scr_bitmap(a0),a0
	add.l	#BEAM_Y*ROW_BYTES,a0
	move.w	BeamX(a5),d0
	moveq	#15,d4
	and.w	d0,d4
	ror.w	#4,d4				; the shift, as bltcon0 wants it
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,a0				; the beam's top left word
	; rows BeamTop to BeamBottom of the image show
	moveq	#0,d1
	move.b	BeamTop(a5),d1
	moveq	#0,d2
	move.b	BeamBottom(a5),d2
	cmp.w	d1,d2
	bcc	.Above
	move.w	d1,d2				; none of it
.Above	move.w	d1,d0
	beq	.Image
	bsr	BeamClear
.Image	move.w	d2,d0
	sub.w	d1,d0
	beq	.Below
	move.w	ArcadeFrame(a5),d3		; the colour sets go 0, 0, 1, 2, four frames each
	lsr.w	#2,d3
	and.w	#3,d3
	beq	.Set
	subq.w	#1,d3
.Set	mulu.w	#BEAM_SET,d3
	lea	Beam,a1
	add.l	d3,a1
	mulu.w	#8*BEAM_LINE,d1
	add.l	d1,a1
	move.w	d0,d3				; rows to lines of every plane, as bltsize wants them
	lsl.w	#8,d3
	lsl.w	#ROW_SIZE_SHIFT-8,d3
	or.w	#BLIT_WORDS,d3
	or.w	#COPY,d4
	swap	d4
	clr.w	d4				; bltcon0:bltcon1
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.l	#FIRST_WORDS,bltafwm(a6)
	move.w	#-2,bltamod(a6)			; the image has no extra word: step back over it
	move.w	#PLANE_BYTES-BLIT_WORDS*2,bltdmod(a6)
	move.l	a1,bltapt(a6)
	move.l	a0,bltdpt(a6)
	move.w	d3,bltsize(a6)
	mulu.w	#8*ROW_BYTES,d0
	add.l	d0,a0
.Below	moveq	#BEAM_ROWS,d0
	sub.w	d2,d0
	bne	BeamClear
.None	rts

;--
; BeamClear
; Blank some rows of the beam's place.
; In:       a0 = their top left word, d0.w = how many rows, 1 or more, a6 = CUSTOM
; Out:      a0 = the row after them
; Clobbers: d0
BeamClear:
	WAITBLIT
	move.l	#CLEAR<<16,bltcon0(a6)
	move.w	#PLANE_BYTES-BLIT_WORDS*2,bltdmod(a6)
	move.l	a0,bltdpt(a6)
	lsl.w	#8,d0
	lsl.w	#ROW_SIZE_SHIFT-8,d0
	or.w	#BLIT_WORDS,d0
	move.w	d0,bltsize(a6)
	lsr.w	#8,d0
	lsr.w	#ROW_SIZE_SHIFT-8,d0
	mulu.w	#8*ROW_BYTES,d0
	add.l	d0,a0
	rts
