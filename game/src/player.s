; Player: the fighter, its shots, and what they hit.
;
; Ported from the arcade (the model is motion/shots.py). The fighter moves
; one pixel and two pixels on alternate arcade frames while the stick is
; held. Two shots can be in flight; a shot climbs 6 lines an arcade frame
; and is gone above the screen. Each frame, after it has moved, a shot hits
; every enemy within 5 pixels to the side and from 6 above to 5 below (the
; arcade halves the y's, so in two-line steps). A boss takes two hits; the
; first only changes its colour. A destroyed enemy scores by its kind,
; double if it was flying, and a boss shot while diving scores by how many
; escorts it set off with instead: 400, 800 or 1600.
;
; Where this differs from the arcade, by decision: both shots share one
; hardware sprite, which needs them 9 lines apart, so a second press that
; comes sooner than that waits a frame or two instead of firing at once.
; A press while both shots are in flight is lost, as in the arcade.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"gfx.i"

	xdef	PlayerInit
	xdef	PlayerInput
	xdef	PlayerTick
	xdef	ShotsTick
	xdef	FighterHits
	xdef	PlayerEnter
	xdef	ScoreAdd
	xref	FlightPlace
	xref	FlightImage
	xref	Enemies
	xref	RescueStart

SHIP_LEFT	equ	$12			; the fighter's sprite x stays within these
SHIP_RIGHT	equ	$e1
SHIP_RIGHT_DUAL	equ	$d1			;   and the left one of two within this
DUAL_STEP	equ	15			; the second fighter is this far right of the first
BOSS_OBJECTS	equ	$30			; the bosses' object numbers are this and the next 7
EXTRA_OBJECTS	equ	$38			; and those that only fly through are this and the next 7
OBJECT_GROUP	equ	$f8
SHOT_SPEED	equ	6			; lines per arcade frame
SHOT_TOP	equ	40			; a shot above this sprite y is gone
SHOT_GAP	equ	9			; lines the first shot must be up before the second fires
HIT_ASIDE	equ	5			; a hit is within this many pixels to either side,
HIT_ABOVE	equ	3			;   and with the enemy at most this far above
HIT_BELOW	equ	2			;   or below, in two-line steps
SY_MASK		equ	$1ff			; the arcade's sprite y has 9 bits
AUTO_FIRE	equ	16			; test builds: frames between presses
UPRIGHT		equ	6*FRAME_SIZE		; an enemy's upright image
BOSS_MASK	equ	7			; a boss's number is (object and this) / 2
TIMER_FRAMES	equ	32			; arcade frames per count of GameTimer
STEP_FRAMES	equ	4			; arcade frames per step of the fighter's explosion
BLOWN_STEPS	equ	15			; steps of it
BLOWN_PAUSE	equ	4			; GameTimer from the fighter's loss until the next one is due
READY_PAUSE	equ	3			;   while the new fighter cannot yet fire or be hit
OVER_PAUSE	equ	6			;   after the last fighter
RETURN_SX	equ	$7a			; where a new fighter appears
TIME_BACK	equ	30			; StageTime added when it does,
STAGE_TIME	equ	120			;   up to the stage's starting time
TOUCH_ASIDE	equ	6			; the fighter is hit by anything within this many pixels to the side
TOUCH_UP_DOWN	equ	3			;   and this many two-line steps above or below
SHIP_HALF_Y	equ	SHIP_SY/2
NO_OBJECT	equ	$7f			; above every object number
SHIP_UPRIGHT	equ	6			; the fighter's frame when it points up
CHALLENGE_MASK	equ	3			; a stage whose number ends in these two bits set is a challenging stage
WAVE_BONUSES	equ	4
FIRST_ENEMY	equ	$08			; objects below this are captured fighters
POPUP_1000	equ	3
; the arcade's colour sets, which decide an enemy's sound and score
BLUE_BOSS	equ	1
RED_FIGHTER	equ	7

	section	code,code

;--
; PlayerInit
; A new game's fighter: in the middle, in play, no shots in flight, the reserve full.
; In:       a5 = state
; Out:      -
; Clobbers: a0
PlayerInit:
	move.w	#(PLAY_WIDTH-16)/2,ShipX(a5)
	move.b	#PS_PLAYING,PlayerState(a5)
	st	InPlay(a5)
	clr.b	FighterStep(a5)
	clr.b	GameTimer(a5)
	move.b	#RESERVE,Lives(a5)
	bsr	Upright
	if	DUAL_START
	st	Dual(a5)
	else
	clr.b	Dual(a5)
	endc
	clr.b	Docking(a5)
	clr.b	Bang2Step(a5)
	lea	Shots(a5),a0
	rept	SHOTS*sh_SIZEOF/2
	clr.w	(a0)+
	endr
	clr.b	PadLeft(a5)
	clr.b	FireWas(a5)
	clr.b	FirePending(a5)
	clr.b	MoveFlag(a5)
	if	REPORTING
	st	PadRight(a5)
	else
	clr.b	PadRight(a5)
	endc
	rts

;--
; Upright
; The fighter as it normally is: at the bottom, pointing up, drawn.
; In:       a5 = state
; Out:      -
; Clobbers: -
Upright:
	move.w	#SHIP_SY,ShipSY(a5)
	move.b	#SHIP_UPRIGHT,ShipCode(a5)
	clr.b	ShipCtrl(a5)
	clr.b	ShipGone(a5)
	rts

;--
; PlayerEnter
; A game's first fighter comes on: it can move, and after the pause it is in play.
; In:       a5 = state
; Out:      -
; Clobbers: -
PlayerEnter:
	bsr	Upright
	move.w	#RETURN_SX-DISPLAY_SX,ShipX(a5)
	move.b	#READY_PAUSE,GameTimer(a5)
	move.b	#PS_READY,PlayerState(a5)
	rts

;--
; PlayerInput
; Once a displayed frame: read the stick and the fire button.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1
PlayerInput:
	if	REPORTING
	; a test build plays itself: from side to side, a press every AUTO_FIRE frames
	move.w	ShipX(a5),d0
	add.w	#DISPLAY_SX,d0
	move.w	#SHIP_RIGHT,d1
	tst.b	Dual(a5)
	beq	.Edge
	move.w	#SHIP_RIGHT_DUAL,d1
.Edge	cmp.w	d1,d0
	bcs	.NotRight
	st	PadLeft(a5)
	clr.b	PadRight(a5)
.NotRight
	cmp.w	#SHIP_LEFT,d0
	bcc	.NotLeft
	st	PadRight(a5)
	clr.b	PadLeft(a5)
.NotLeft
	moveq	#AUTO_FIRE-1,d0
	and.w	FlightFrame(a5),d0
	bne	.Read
	st	FirePending(a5)
	else
	move.w	joy1dat(a6),d0
	btst	#JOYB_RIGHT,d0
	sne	PadRight(a5)
	btst	#JOYB_LEFT,d0
	sne	PadLeft(a5)
	; a press is the button down now and up last frame
	btst	#CIAAB_FIRE1,CIAA_PRA
	seq	d0
	move.b	FireWas(a5),d1
	move.b	d0,FireWas(a5)
	not.b	d1
	and.b	d0,d1
	beq	.Read
	st	FirePending(a5)
	endc
.Read	rts

;--
; PlayerTick
; One arcade frame of the fighter: move it, and fire if a press is waiting.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0-a1
PlayerTick:
	; the timer for the pauses around losing a fighter
	moveq	#TIMER_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Timed
	tst.b	GameTimer(a5)
	beq	.Timed
	subq.b	#1,GameTimer(a5)
	; one of two fighters blowing up: it steps as a lone fighter's explosion does
.Timed	moveq	#STEP_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	subq.w	#STEP_FRAMES-1,d0
	bne	.State
	tst.b	Bang2Step(a5)
	beq	.State
	subq.b	#1,Bang2Step(a5)
.State	move.b	PlayerState(a5),d0
	beq	.Fly				; PS_PLAYING
	subq.b	#PS_READY,d0
	beq	.Ready
	bcs	.Away
	subq.b	#PS_OVER-PS_READY,d0
	bne	.Done				; PS_ABSENT: not there yet
	; PS_OVER: after the pause, a new game
	tst.b	GameTimer(a5)
	bne	.Done
	st	NewGame(a5)
	rts
.Away	addq.b	#PS_READY-PS_BLOWN,d0
	bne	.Returning
	; PS_BLOWN: the explosion steps on frames 3, 7, 11..., as the arcade's object for the fighter does
	moveq	#STEP_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	subq.w	#STEP_FRAMES-1,d0
	bne	.Blown
	tst.b	FighterStep(a5)
	beq	.Blown
	subq.b	#1,FighterStep(a5)
.Blown	tst.b	GameTimer(a5)
	bne	.Done
	tst.b	RescueOn(a5)			; a rescued fighter on its way down takes its place
	bne	.Done
	move.b	#PS_OVER,PlayerState(a5)	; no fighter left in reserve: the game is over
	move.b	#OVER_PAUSE,GameTimer(a5)
	tst.b	Lives(a5)
	beq	.Done
	subq.b	#1,Lives(a5)
	move.b	#PS_RETURNING,PlayerState(a5)
	rts
	; PS_RETURNING: the next fighter comes on once the divers are home
.Returning
	tst.w	Flying(a5)
	bne	.Done
	bsr	Upright
	move.w	#RETURN_SX-DISPLAY_SX,ShipX(a5)
	moveq	#TIME_BACK,d0			; the stage gets some of its time back
	add.b	StageTime(a5),d0
	cmp.b	#STAGE_TIME,d0
	bls	.Time
	moveq	#STAGE_TIME,d0
.Time	move.b	d0,StageTime(a5)
	move.b	#READY_PAUSE,GameTimer(a5)
	move.b	#PS_READY,PlayerState(a5)
	rts
	; PS_READY: it can move; after the pause it is in play
.Ready	tst.b	GameTimer(a5)
	bne	.Fly
	move.b	#PS_PLAYING,PlayerState(a5)
	st	InPlay(a5)

.Fly	tst.b	Docking(a5)			; making room for a rescued fighter: no stick, no fire
	bne	.Done
	move.w	ShipX(a5),d2
	add.w	#DISPLAY_SX,d2			; as the arcade counts
	move.b	PadLeft(a5),d0
	move.b	PadRight(a5),d1
	cmp.b	d0,d1
	beq	.Still
	; a pixel and two pixels on alternate frames
	moveq	#1,d0
	bchg	#0,MoveFlag(a5)
	beq	.Step
	moveq	#2,d0
.Step	tst.b	d1
	beq	.Left
	cmp.w	#SHIP_RIGHT_DUAL,d2
	bcs	.Right
	tst.b	Dual(a5)			; two fighters stop sooner
	bne	.Fire
	cmp.w	#SHIP_RIGHT,d2
	bcc	.Fire
.Right	add.w	d0,d2
	bra	.Moved
.Left	cmp.w	#SHIP_LEFT,d2
	bcs	.Fire
	sub.w	d0,d2
.Moved	move.w	d2,d0
	sub.w	#DISPLAY_SX,d0
	move.w	d0,ShipX(a5)
	bra	.Fire
.Still	clr.b	MoveFlag(a5)

.Fire	tst.b	InPlay(a5)
	beq	.Lost				; no firing before the fighter is in play
	tst.b	FirePending(a5)
	beq	.Done
	lea	Shots(a5),a0
	lea	sh_SIZEOF(a0),a1		; the other shot
	tst.w	sh_x(a0)
	beq	.Free
	exg	a0,a1
	tst.w	sh_x(a0)
	bne	.Lost				; both are in flight: the press is lost
.Free	tst.w	sh_x(a1)
	beq	.Launch
	; both shots share a sprite: the press waits until the other shot has made room
	move.w	#SHIP_SY,d0
	sub.w	sh_y(a1),d0
	cmp.w	#SHOT_GAP,d0
	blt	.Done
.Launch	move.w	d2,sh_x(a0)
	move.b	Dual(a5),sh_wide(a0)
	move.w	#SHIP_SY,sh_y(a0)
	SOUND	SND_SHOT
.Lost	clr.b	FirePending(a5)
.Done	rts

;--
; ShotsTick
; One arcade frame of the shots: move them, and see what they hit.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a3
ShotsTick:
	lea	Shots(a5),a3
	bsr	Shot
	lea	Shots+sh_SIZEOF(a5),a3
	; falls through

;--
; Shot
; Move one shot and destroy what it hits.
; In:       a3 = the shot, a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a2
Shot:	move.w	sh_x(a3),d6
	beq	.None
	subq.w	#SHOT_SPEED,sh_y(a3)
	move.w	sh_y(a3),d7
	cmp.w	#SHOT_TOP,d7
	blt	.Gone
	lsr.w	#1,d7				; the arcade compares y's halved
	clr.b	ShotHit(a5)

	; the formation: each row within reach, then whoever is there in it
	lea	HomeX(a5),a2
	moveq	#FORM_ROWS-1,d4
.Row	move.w	d4,d1
	add.w	d1,d1
	move.b	HOME_ROWS+2*STRIP_ROWS(a2,d1.w),d0
	lsr.b	#1,d0
	sub.b	d7,d0
	addq.b	#HIT_ABOVE,d0
	cmp.b	#HIT_ABOVE+HIT_BELOW,d0
	bhi	.NextRow
	lea	FormPresent(a5),a0
	move.w	(a0,d1.w),d3
	beq	.NextRow
	moveq	#HOME_COLUMNS-1,d2
.Column	btst	d2,d3
	beq	.NextColumn
	move.w	d2,d1
	add.w	d1,d1
	move.b	(a2,d1.w),d0
	sub.b	d6,d0
	bsr	Aside
	beq	.NextColumn
	bsr	HitPlaced
.NextColumn
	dbf	d2,.Column
.NextRow
	dbf	d4,.Row

	; the captured fighter in its place above its boss
	cmp.b	#CS_PLACED,CaptiveState(a5)
	bne	.Flights
	move.w	CaptiveY(a5),d0
	lsr.w	#1,d0
	sub.b	d7,d0
	addq.b	#HIT_ABOVE,d0
	cmp.b	#HIT_ABOVE+HIT_BELOW,d0
	bhi	.Flights
	move.w	CaptiveX(a5),d0
	sub.b	d6,d0
	bsr	Aside
	beq	.Flights
	st	ShotHit(a5)
	clr.b	ShotFlying(a5)
	moveq	#0,d5
	move.b	CaptiveObj(a5),d5
	move.w	CaptiveX(a5),d0
	subq.w	#SPRITE_X,d0
	move.w	CaptiveY(a5),d1
	sub.w	#SPRITE_Y,d1
	sub.l	a1,a1
	bsr	Destroy

	; the flights, in the air or just landed
.Flights
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d4
.Flight	moveq	#1<<FLB_ACTIVE|1<<FLB_LANDED,d0
	and.b	fl_flags(a0),d0
	beq	.NextFlight
	bsr	FlightPlace
	move.w	d1,d2
	add.w	#SPRITE_Y,d2
	and.w	#SY_MASK,d2
	lsr.w	#1,d2
	sub.b	d7,d2
	addq.b	#HIT_ABOVE,d2
	cmp.b	#HIT_ABOVE+HIT_BELOW,d2
	bhi	.NextFlight
	move.w	d0,d3
	addq.w	#SPRITE_X,d0
	sub.b	d6,d0
	bsr	Aside
	exg	d0,d3
	tst.w	d3
	beq	.NextFlight
	bsr	HitFlying
.NextFlight
	lea	fl_SIZEOF(a0),a0
	dbf	d4,.Flight
	tst.b	ShotHit(a5)
	beq	.None
.Gone	clr.w	sh_x(a3)
.None	rts

;--
; Aside
; Is an enemy within a shot's reach to the side? A dual fighter's shot is two bullets,
; and the arcade's reach for it is a pixel to the left of a single one's, and again
; DUAL_STEP to the right.
; In:       d0.b = the enemy's x less the shot's, a3 = the shot
; Out:      d0 = nonzero and Z clear if it is
; Clobbers: -
Aside:	tst.b	sh_wide(a3)
	bne	.Wide
	addq.b	#HIT_ASIDE,d0
	bra	.Test
.Wide	addq.b	#HIT_ASIDE+1,d0
	cmp.b	#2*HIT_ASIDE,d0
	bls	.Hit
	sub.b	#DUAL_STEP,d0
.Test	cmp.b	#2*HIT_ASIDE,d0
	bls	.Hit
	moveq	#0,d0
	rts
.Hit	moveq	#1,d0
	rts

;--
; FighterHits
; One arcade frame: is the fighter touched by an enemy or a bomb? If so it is lost, and
; so is the enemy.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a3
FighterHits:
	if	BOMB_STRESS
	rts					; the timing test: nothing hurts the fighter
	endc
	tst.b	InPlay(a5)
	beq	.Safe
	cmp.b	#PS_PLAYING,PlayerState(a5)	; not one in the tractor beam
	bne	.Safe
	tst.b	Docking(a5)			; nor one making room for a rescued fighter
	bne	.Safe
	tst.b	Dual(a5)
	beq	.First
	; the second of two first, as the arcade: if it is lost the first plays on
	move.w	ShipX(a5),d6
	add.w	#DISPLAY_SX+DUAL_STEP,d6
	bsr	Touched
	tst.w	d7
	beq	.First
	move.w	ShipX(a5),d0
	add.w	#DUAL_STEP,d0
	bsr	HalfLost
.First	move.w	ShipX(a5),d6
	add.w	#DISPLAY_SX,d6
	bsr	Touched
	tst.w	d7
	beq	.Safe
	tst.b	Dual(a5)
	beq	.Lost
	; the first of two: the second is the fighter from now on
	move.w	ShipX(a5),d0
	add.w	#DUAL_STEP,ShipX(a5)
	bra	HalfLost
	; the fighter is lost
.Lost	move.b	#PS_BLOWN,PlayerState(a5)
	clr.b	InPlay(a5)
	move.b	#BLOWN_STEPS,FighterStep(a5)
	move.b	#BLOWN_PAUSE,GameTimer(a5)
	clr.b	FirePending(a5)
	LOG	#STAGE_FIGHTER_LOST,Lives(a5)
	if	SOUND_TEST=0
	move.b	#1,Sound+snd_bang(a5)
	endc
.Safe	rts

;--
; HalfLost
; One of two fighters is lost: it blows up where it was and the other plays on.
; Bosses may try to capture again.
; In:       d0.w = its playfield x, a5 = state
; Out:      -
; Clobbers: -
HalfLost:
	move.w	d0,Bang2X(a5)
	move.b	#BLOWN_STEPS,Bang2Step(a5)
	clr.b	Dual(a5)
	clr.b	Capturing(a5)
	if	SOUND_TEST=0
	move.b	#1,Sound+snd_bang(a5)
	endc
	rts

;--
; Touched
; Is a fighter touched by an enemy or a bomb? The enemy is destroyed, the bomb used up.
; In:       d6.w = the fighter's sprite x, a5 = state
; Out:      d7.w = nonzero if it is
; Clobbers: d0-d6, a0-a3
Touched:
	moveq	#0,d7				; nonzero once something has touched it
	; an enemy in flight: only once the stage's waves are all in. If several touch, the
	; arcade takes the one with the lowest object number.
	tst.b	WavesIn(a5)
	beq	.Bombs
	sub.l	a3,a3
	moveq	#NO_OBJECT,d5
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d4
.Flight	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.NextFlight
	bsr	FlightPlace
	move.w	d0,d2
	addq.w	#SPRITE_X,d2
	sub.b	d6,d2
	addq.b	#TOUCH_ASIDE,d2
	cmp.b	#2*TOUCH_ASIDE,d2
	bhi	.NextFlight
	move.w	d1,d2
	add.w	#SPRITE_Y,d2
	and.w	#SY_MASK,d2
	lsr.w	#1,d2
	sub.b	#SHIP_HALF_Y,d2
	addq.b	#TOUCH_UP_DOWN,d2
	cmp.b	#2*TOUCH_UP_DOWN,d2
	bhi	.NextFlight
	cmp.b	fl_obj(a0),d5
	bls	.NextFlight
	move.b	fl_obj(a0),d5
	move.l	a0,a3
.NextFlight
	lea	fl_SIZEOF(a0),a0
	dbf	d4,.Flight
	move.l	a3,d0
	beq	.Bombs
	moveq	#1,d7
	move.l	a3,a0
	bsr	FlightPlace
	movem.w	d6-d7,-(sp)
	bsr	HitFlying			; it is hit as by a shot
	movem.w	(sp)+,d6-d7
	; the first bomb that touches is used up
.Bombs	lea	Bombs(a5),a0
	moveq	#BOMBS-1,d4
.Bomb	move.w	bm_x(a0),d2
	beq	.NextBomb
	sub.b	d6,d2
	addq.b	#TOUCH_ASIDE,d2
	cmp.b	#2*TOUCH_ASIDE,d2
	bhi	.NextBomb
	move.w	bm_y(a0),d2
	lsr.w	#1,d2
	sub.b	#SHIP_HALF_Y,d2
	addq.b	#TOUCH_UP_DOWN,d2
	cmp.b	#2*TOUCH_UP_DOWN,d2
	bhi	.NextBomb
	clr.w	bm_x(a0)
	moveq	#1,d7
	bra	.Out
.NextBomb
	addq.l	#bm_SIZEOF,a0
	dbf	d4,.Bomb
.Out	rts

;--
; HitPlaced
; A shot has hit an enemy in its place in the formation.
; In:       d2.w = its column, d4.w = its row, a5 = state
; Out:      -
; Clobbers: d0-d1, d5, a0-a1
HitPlaced:
	st	ShotHit(a5)
	clr.b	ShotFlying(a5)
	bset	d4,FormDirty(a5)		; either way its row's strip changes
	move.w	d4,d0
	mulu.w	#HOME_COLUMNS,d0
	add.w	d2,d0
	lea	FormObj(a5),a0
	moveq	#0,d5
	move.b	(a0,d0.w),d5			; who it is
	lea	ObjKind(a5),a0
	move.w	d5,d0
	lsr.w	#1,d0
	add.w	d0,a0
	move.w	d4,d1
	add.w	d1,d1
	cmp.b	#KIND_BOSS,(a0)
	bne	.Destroy
	; a boss's first hit: it changes colour
	move.b	#KIND_BOSSHIT,(a0)
	lea	FormAlt(a5),a1
	move.w	(a1,d1.w),d0
	bset	d2,d0
	move.w	d0,(a1,d1.w)
	SOUND	SND_HIT_BOSS1
	LOG	#STAGE_BOSS_HIT,d5
	rts
.Destroy
	lea	FormPresent(a5),a1
	move.w	(a1,d1.w),d0
	bclr	d2,d0
	move.w	d0,(a1,d1.w)
	; where it was, in the buffer
	lea	HomeX(a5),a1
	add.w	d2,a1
	moveq	#0,d0
	move.b	(a1,d2.w),d0
	subq.w	#SPRITE_X,d0
	lea	HomeX+HOME_ROWS+2*STRIP_ROWS(a5),a1
	add.w	d4,a1
	moveq	#0,d1
	move.b	(a1,d4.w),d1
	sub.w	#SPRITE_Y,d1
	sub.l	a1,a1				; upright
	bra	Destroy

;--
; HitFlying
; A shot has hit an enemy in flight, or one that has just landed.
; In:       a0 = its flight, d0.w = its x in buffer pixels, d1.w = its y in buffer rows,
;           a5 = state
; Out:      -
; Clobbers: d2-d3, d5, a1
HitFlying:
	st	ShotHit(a5)
	moveq	#0,d5
	move.b	fl_obj(a0),d5
	lea	ObjKind(a5),a1
	move.w	d5,d2
	lsr.w	#1,d2
	add.w	d2,a1
	cmp.b	#KIND_BOSS,(a1)
	bne	.Destroy
	move.b	#KIND_BOSSHIT,(a1)
	SOUND	SND_HIT_BOSS1
	LOG	#STAGE_BOSS_HIT,d5
	rts
.Destroy
	btst	#FLB_ACTIVE,fl_flags(a0)	; one that has landed counts as in its place
	sne	ShotFlying(a5)
	; its image as it flies, for the moment before the blast
	movem.l	d4/a0/a3,-(sp)
	move.l	a0,a3
	bsr	FlightImage
	move.l	a0,a1
	movem.l	(sp)+,d4/a0/a3
	clr.b	fl_flags(a0)
	; falls through

;--
; Destroy
; An enemy is destroyed: its sound, its score, and a blast where it was.
; In:       d0.w = its x in buffer pixels, d1.w = its y in buffer rows, d5.w = object,
;           a1 = its image, or 0 for its kind's upright one, ShotFlying(a5), a5 = state
; Out:      -
; Clobbers: a1
Destroy:
	movem.l	d2-d4/a0,-(sp)
	; the boss that was out to capture: another may try. The captured fighter: likewise.
	cmp.b	CaptureBoss(a5),d5
	bne	.Other
	clr.b	Capturing(a5)
	move.b	#1,CaptureBoss(a5)
.Other	cmp.b	#FIRST_ENEMY,d5
	bcc	.Enemy
	clr.b	Capturing(a5)
	clr.b	CaptiveState(a5)
	; a boss shot in flight with the fighter it captured flying along: the fighter is free
.Enemy	moveq	#OBJECT_GROUP-256,d2
	and.w	d5,d2
	cmp.b	#BOSS_OBJECTS,d2
	bne	.Kind
	tst.b	ShotFlying(a5)
	beq	.Kind
	cmp.b	#CS_FLYING,CaptiveState(a5)
	bne	.Kind
	moveq	#BOSS_MASK,d2
	and.w	d5,d2
	cmp.b	CaptiveObj(a5),d2
	bne	.Kind
	bsr	RescueStart
.Kind
	lea	ObjKind(a5),a0
	move.w	d5,d2
	lsr.w	#1,d2
	moveq	#0,d3
	move.b	(a0,d2.w),d3			; its kind
	move.l	a1,d2
	bne	.Image
	move.l	d3,d2
	moveq	#KIND_SHIFT,d4
	lsl.l	d4,d2
	add.l	#Enemies+UPRIGHT,d2
	move.l	d2,a1
.Image	lea	KindColour(pc),a0
	move.b	(a0,d3.w),d3			; the arcade's colour set for it
	; the sound: boss, butterfly, bee by colour
	if	SOUND_TEST=0
	moveq	#SND_FIGHTER_LOST,d2		; the captured fighter has its own sound
	cmp.b	#RED_FIGHTER,d3
	beq	.Sound
	move.b	d3,d2
	subq.b	#1,d2
	and.w	#3,d2
	add.w	d2,d2
	addq.w	#SND_HIT_BOSS2,d2
.Sound	lea	Sound(a5),a0
	move.b	#1,(a0,d2.w)
	endc
	; the score: by colour, twice over if it was flying
	moveq	#0,d2
	move.b	d3,d2
	add.w	d2,d2
	lea	Points(pc),a0
	move.w	(a0,d2.w),d2
	moveq	#POPUP_NONE,d4
	bsr	ScoreAdd
	tst.b	ShotFlying(a5)
	beq	.Scored
	bsr	ScoreAdd
	addq.b	#1,FlyingHits(a5)
	; a challenging stage: the eighth of a wave shot while flying brings the wave's bonus
	subq.b	#1,WaveHits(a5)
	bne	.Boss
	moveq	#CHALLENGE_MASK,d2
	and.w	Stage(a5),d2
	subq.w	#CHALLENGE_MASK,d2
	bne	.Boss
	move.w	Stage(a5),d2			; the bonus grows every eight stages, up to stage 32
	lsr.w	#3,d2
	cmp.w	#WAVE_BONUSES-1,d2
	bls	.Wave
	moveq	#WAVE_BONUSES-1,d2
.Wave	lea	WavePopups(pc),a0
	move.b	(a0,d2.w),d4
	add.w	d2,d2
	lea	WavePoints(pc),a0
	move.w	(a0,d2.w),d2
	bsr	ScoreAdd
	bra	.Scored
.Boss	cmp.b	#RED_FIGHTER,d3
	bne	.Blue
	moveq	#POPUP_1000,d4			; the captured fighter shot while flying: 1000 shows
	bra	.Scored
.Blue	cmp.b	#BLUE_BOSS,d3
	bne	.Scored
	moveq	#EXTRA_OBJECTS,d2		; not one that only flies through: it set off with nobody
	and.w	d5,d2
	cmp.w	#EXTRA_OBJECTS,d2
	beq	.Scored
	; a boss shot while diving: more for the escorts it set off with, and the total pops up
	moveq	#BOSS_MASK,d2
	and.w	d5,d2
	lsr.w	#1,d2
	lea	BossBonus(a5),a0
	moveq	#0,d4
	move.b	(a0,d2.w),d4
	move.w	d4,d2
	add.w	d2,d2
	lea	BonusPoints(pc),a0
	move.w	(a0,d2.w),d2
	bsr	ScoreAdd
.Scored	subq.b	#1,Alive(a5)
	LOG	#STAGE_KILLED,d5
	LOG	#STAGE_SCORE_HI,Score+2(a5)
	LOG	#STAGE_SCORE_LO,Score+3(a5)
	; the blast, if there is room for one
	lea	Blasts(a5),a0
	moveq	#BLASTS-1,d2
.Find	tst.b	bl_live(a0)
	beq	.Blast
	lea	bl_SIZEOF(a0),a0
	dbf	d2,.Find
	bra	.Out
.Blast	st	bl_live(a0)
	move.w	d0,bl_x(a0)
	move.w	d1,bl_y(a0)
	move.l	a1,bl_image(a0)
	move.b	d5,bl_obj(a0)
	clr.b	bl_step(a0)
	move.b	d4,bl_popup(a0)
.Out	movem.l	(sp)+,d2-d4/a0
	rts

; points by the arcade's colour set, as decimal digits: green boss (not destroyed by one
; hit), blue boss 150, butterfly 80, bee 50, the challenging stages' three 80, red fighter 500
Points:	dc.w	0,$0150,$0080,$0050,$0080,$0080,$0080,$0500
; a challenging stage's bonus for all eight of a wave, by stage / 8: 1000, 1500, 2000, 3000
WavePoints:
	dc.w	$1000,$1500,$2000,$3000
; and the pop-up that shows it (the 2000 and 3000 ones are two tiles wide: not drawn yet)
WavePopups:
	dc.b	3,4,POPUP_NONE,POPUP_NONE
; and what a boss shot while diving adds for 0, 1 or 2 escorts: 400, 800, 1600 in all
BonusPoints:
	dc.w	$0100,$0500,$1300
; the colour set of each kind of enemy (the KIND_ order)
KindColour:
	dc.b	0,1,2,3,4,5,6,2,2,2,RED_FIGHTER
	even

;--
; ScoreAdd
; Add to the score.
; In:       d2.l = points, as decimal digits, a5 = state
; Out:      -
; Clobbers: -
ScoreAdd:
	movem.l	a0-a1,-(sp)
	move.l	d2,ScoreStep(a5)
	lea	Score+4(a5),a0
	lea	ScoreStep+4(a5),a1
	and.b	#$ef,ccr			; no carry in
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
	movem.l	(sp)+,a0-a1
	rts
