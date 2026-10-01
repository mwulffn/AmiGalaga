; Game: one frame of the playfield. So far: the stage's enemies fly in,
; turned the way they are heading, and take their places in the formation.
;
; Time: the arcade's own logic counts arcade frames, and a displayed frame
; is FIFTHS fifths of one. Clock holds how far into a displayed frame the
; next arcade frame begins; each one that begins in this frame gets a tick,
; so on PAL there are two in every fifth frame. A flight launched by a tick
; waits out the part of the frame before its tick, which keeps enemies
; that follow each other evenly spaced.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"gfx.i"

	xdef	GameInit
	xdef	GameFrame
	xdef	FlightPlace
	xdef	FlightImage
	xref	StageTick
	xref	FlightStep
	xref	FlyersErase
	xref	FlyersBegin
	xref	FlyerDraw
	xref	FormationCompose
	xref	FormationDraw
	xref	FormationTick
	xref	DivesTick
	xref	PlayerInit
	xref	PlayerInput
	xref	PlayerTick
	xref	ShotsTick
	xref	BlastsTick
	xref	BlastsDraw
	xref	BombsDrop
	xref	BombsFall
	xref	BombsDraw
	xref	FighterHits
	xref	FlowInit
	xref	FlowTick
	xref	TextDraw
	xref	StageIdle
	xref	StarsTick
	xref	CaptureInit
	xref	TitleTick
	xref	ScoresInit
	if	REPORTING=0
	xref	TitleShow
	xref	ScoresInsert
	endc
	xdef	GameStart
	xref	FormationInit
	xref	TransformTick
	xref	TransformHome
	xref	CaptureTick
	xref	BeamDraw
	xref	HomeRc
	xref	Enemies
	if	STAGE_TEST
	xdef	StageLog
	endc

FIRST_ENEMY	equ	$08			; objects below this are captured fighters
UPRIGHT_FRAME	equ	6			; an enemy's upright frame
FLYING_BITS	equ	1<<FLB_ACTIVE|1<<FLB_LANDED
QUADRANT_BITS	equ	2
QUADRANTS	equ	4
HALF_STEP	equ	21			; half of 15 degrees, where a quadrant is 256
FLIP_SHIFT	equ	11			; FLIP_SIZE as a shift
POSITION_SHIFT	equ	7			; a flight's position to pixels
X_MASK		equ	$ff			; the arcade's sprites have 8 bits of x

	section	code,code

;--
; GameInit
; At the start, and when a game is over: nothing on the playfield, then the title (a test
; build goes straight into a game).
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
GameInit:
	tst.b	NewGame(a5)			; a game after the first keeps the clocks running
	bne	.Again
	clr.w	Clock(a5)
	clr.w	ArcadeFrame(a5)
	clr.w	FlightFrame(a5)
	clr.w	FormNext(a5)
	if	STAGE_TEST
	move.l	#StageLog,StageLogPtr(a5)
	endc
	bsr	FormationInit			; from then on a stage's start puts the formation at rest
	move.b	#RANK,Rank(a5)			; the options as they are until someone changes them
	clr.b	OptRank(a5)
	move.b	#RESERVE,OptLives(a5)
	bsr	ScoresInit
.Again
	clr.b	NewGame(a5)
	lea	Blasts(a5),a0
	moveq	#BLASTS-1,d0
.Blast	clr.b	bl_live(a0)
	lea	bl_SIZEOF(a0),a0
	dbf	d0,.Blast
	lea	Bombs(a5),a0
	moveq	#BOMBS-1,d0
.Bomb	clr.w	bm_x(a0)
	addq.l	#bm_SIZEOF,a0
	dbf	d0,.Bomb
	bsr	StageIdle
	if	REPORTING
	; a test build plays itself: straight into a game
	else
	; the game that is over may have one of the best scores; then the title
	bsr	ScoresInsert
	bra	TitleShow
	endc
	; falls through

;--
; GameStart
; A game begins: its fighters and score, then its opening (flow.s).
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
GameStart:
	clr.l	Score(a5)
	bsr	PlayerInit
	bsr	CaptureInit
	bra	FlowInit

;--
; GameFrame
; One displayed frame: launch, fly, land, and draw the playfield into the back screen.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
GameFrame:
	tst.b	NewGame(a5)
	beq	.Play
	bsr	GameInit
.Play	tst.b	Mode(a5)			; the title or the options: the stick works them
	beq	.Game
	bsr	TitleTick
.Game	move.w	ShipX(a5),d0
	add.w	#DISPLAY_SX,d0
	move.b	d0,FighterX(a5)
	bsr	PlayerInput
	clr.w	TicksNow(a5)
	clr.w	StarSteps(a5)

	; an arcade frame for each one that begins in this displayed frame
.Tick	move.w	Clock(a5),d6
	cmp.w	#FIFTHS,d6
	bcc	.Ticked
	bsr	StageTick
	bsr	DivesTick
	bsr	TransformTick
	bsr	FormationTick
	bsr	PlayerTick
	bsr	CaptureTick
	bsr	BombsDrop
	bsr	BlastsTick
	bsr	FlowTick
	bsr	StarsTick
	addq.w	#1,TicksNow(a5)
	addq.w	#1,ArcadeFrame(a5)
	addq.w	#FRAME_FIFTHS,Clock(a5)
	bra	.Tick
.Ticked	subq.w	#FIFTHS,Clock(a5)
	MARK	PROF_LOGIC
	move.w	StarSteps(a5),StarSpeed(a5)	; the vertical blank scrolls the stars by this
	if	STAGE_TEST
	; checksum = (checksum rol 1) + x, over the formation's 16 positions
	lea	HomeX(a5),a0
	moveq	#0,d0
	moveq	#HOME_ENTRIES-1,d1
.Sum	rol.b	#1,d0
	add.b	(a0),d0
	addq.l	#2,a0
	dbf	d1,.Sum
	LOG	#STAGE_FORMATION,d0
	endc

	lea	Flights(a5),a0
	lea	FLIGHT_SLOTS*fl_SIZEOF(a0),a3
.Fly	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.Flown
	bsr	FlightStep
	tst.w	d0
	beq	.Flown
	LOG	d0,fl_obj(a0)
	subq.w	#FLIGHT_HOME,d0
	bne	.Left
	cmp.b	#FIRST_ENEMY,fl_obj(a0)
	bcs	.Captive
	bset	#FLB_LANDED,fl_flags(a0)
	move.b	fl_obj(a0),d0
	cmp.b	Special(a5),d0
	bne	.Flown
	bsr	TransformHome			; the one that transformed is its old self again
	bra	.Flown
	; the captured fighter is back in its place, which is no strip's
.Captive
	move.b	#CS_PLACED,CaptiveState(a5)
	bra	.Flown
	; its script ended: it has left the stage, and if it was one of the stage's own it is one fewer
.Left	move.b	fl_obj(a0),d0
	cmp.b	#FIRST_ENEMY,d0
	bcc	.Enemy
	clr.b	CaptiveState(a5)		; the captured fighter has flown off alone
	clr.b	Capturing(a5)
	subq.b	#1,Alive(a5)
	bra	.Flown
.Enemy
	subq.b	#1,Alive(a5)
.Flown	lea	fl_SIZEOF(a0),a0
	cmp.l	a3,a0
	bne	.Fly

	; now that the enemies have moved: the shots and bombs move, and hit, once for each
	; arcade frame that began in this displayed frame
	move.w	ArcadeFrame(a5),d0
	sub.w	TicksNow(a5),d0
	move.w	d0,TickFrame(a5)
	MARK	PROF_MOVED
	move.w	TicksNow(a5),d0
	bra	.Shoot
.Shots	move.w	d0,-(sp)
	bsr	ShotsTick
	bsr	BombsFall
	bsr	FighterHits
	addq.w	#1,TickFrame(a5)
	move.w	(sp)+,d0
.Shoot	dbf	d0,.Shots
	addq.w	#1,FlightFrame(a5)
	MARK	PROF_SHOTS

	; A row's strip is rebuilt when someone has just left it; otherwise one row each frame in
	; turn. Whoever has landed in a row is part of its strip from then on.
	moveq	#0,d5
	move.b	FormDirty(a5),d5
	bne	.Dirty
	move.w	FormNext(a5),d0
	bset	d0,d5
	addq.w	#1,d0
	cmp.w	#FORM_ROWS,d0
	bne	.Next
	moveq	#0,d0
.Next	move.w	d0,FormNext(a5)
.Dirty	clr.b	FormDirty(a5)
	moveq	#0,d6				; flights in the air or landed, before any join their strip
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d1
.Count	moveq	#FLYING_BITS,d2
	and.b	fl_flags(a0),d2
	beq	.Counted
	addq.w	#1,d6
.Counted
	lea	fl_SIZEOF(a0),a0
	dbf	d1,.Count
	move.w	d6,-(sp)
	moveq	#0,d0
.Rows	btst	d0,d5
	beq	.Kept
	movem.w	d0/d5,-(sp)
	bsr	Rebuild
	movem.w	(sp)+,d0/d5
.Kept	addq.w	#1,d0
	cmp.w	#FORM_ROWS,d0
	bne	.Rows

	MARK	PROF_STRIPS
	bsr	FlyersErase
	MARK	PROF_ERASED
	bsr	FormationDraw
	MARK	PROF_FORMATION
	bsr	BeamDraw
	bsr	CaptivePlace
	MARK	PROF_BEAM
	bsr	FlyersBegin
	lea	Flights(a5),a3
	moveq	#FLIGHT_SLOTS-1,d7
.Draw	moveq	#FLYING_BITS,d4
	and.b	fl_flags(a3),d4
	beq	.Drawn
	move.l	a3,a0
	bsr	FlightPlace
	cmp.b	#FIRST_ENEMY,fl_obj(a3)
	bcc	.Bob
	; the captured fighter in flight is its sprite, turned as it flies
	addq.w	#SPRITE_X,d0
	add.w	#SPRITE_Y,d1
	move.w	d0,CaptiveX(a5)
	move.w	d1,CaptiveY(a5)
	bsr	FlightFacing
	move.b	d2,CaptiveCode(a5)
	move.b	d3,CaptiveCtrl(a5)
	bra	.Drawn
.Bob	cmp.w	#LAST_FLYER_X,d0
	bhi	.Drawn
	cmp.w	#LAST_FLYER_Y,d1
	bhi	.Drawn
	bsr	FlightImage
	bsr	FlyerDraw
.Drawn	lea	fl_SIZEOF(a3),a3
	dbf	d7,.Draw
	MARK	PROF_FLIGHTS
	bsr	BlastsDraw
	MARK	PROF_BLASTS
	bsr	BombsDraw
	MARK	PROF_BOMBS
	bsr	TextDraw
	MARK	PROF_TEXT
	move.w	(sp)+,d6

	rts


;--
; Rebuild
; Rebuild one row's strip, with whoever has landed in that row now part of it.
; In:       d0.w = row, a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
Rebuild:
	lea	Flights(a5),a0
	lea	HomeRc(pc),a1
	lea	FormPresent(a5),a2
	moveq	#FLIGHT_SLOTS-1,d1
.Land	btst	#FLB_LANDED,fl_flags(a0)
	beq	.Landed
	; strip row = (row entry - first row's) / 2 - rows without a strip, column = entry / 2
	moveq	#0,d2
	move.b	fl_obj(a0),d2
	moveq	#0,d3
	move.b	(a1,d2.w),d3
	sub.w	#HOME_ROWS+2*STRIP_ROWS,d3
	lsr.w	#1,d3
	cmp.w	d0,d3
	bne	.Landed
	move.b	1(a1,d2.w),d2
	lsr.w	#1,d2
	add.w	d3,d3
	move.w	(a2,d3.w),d4
	bset	d2,d4
	move.w	d4,(a2,d3.w)
	clr.b	fl_flags(a0)
.Landed	lea	fl_SIZEOF(a0),a0
	dbf	d1,.Land
	bra	FormationCompose

;--
; CaptivePlace
; The captured fighter in the formation: where its place is now, wings as the formation's.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0-a1
CaptivePlace:
	cmp.b	#CS_PLACED,CaptiveState(a5)
	bne	.Done
	lea	HomeRc(pc),a0
	moveq	#0,d0
	move.b	CaptiveObj(a5),d0
	add.w	d0,a0
	lea	HomeX(a5),a1
	moveq	#0,d0
	move.b	(a0)+,d0
	moveq	#0,d1
	move.b	(a1,d0.w),d1
	move.w	d1,CaptiveY(a5)
	move.b	(a0),d0
	move.b	(a1,d0.w),d1
	move.w	d1,CaptiveX(a5)
	move.w	FrameCount(a5),d0		; wings open and closed with the formation's
	lsr.w	#4,d0
	and.w	#1,d0
	addq.w	#UPRIGHT_FRAME,d0
	move.b	d0,CaptiveCode(a5)
	clr.b	CaptiveCtrl(a5)
.Done	rts

;--
; FlightFacing
; Which frame and flip show the way a flight is heading, by the arcade's rule.
; In:       a3 = its slot
; Out:      d2.w = frame, 0 to 6, d3.w = flip, 0 to 3
; Clobbers: d4
FlightFacing:
	moveq	#UPRIGHT_FRAME,d2
	moveq	#0,d3
	btst	#FLB_LANDED,fl_flags(a3)
	bne	.Done
	; The arcade's rule, on a heading of quadrant (2 bits) and angle within it (8 bits):
	;   a = angle, counted back from the end of the quadrant in quadrants 1 and 3
	;   within half a step of straight up or down (a + 21 > 255): the upright frame
	;   else frame = (a + 21) * 3 / 128: six frames, 15 degrees apart, from pointing left
	;   flip by quadrant: its hardware mirrors the frame to get the other directions
	move.w	fl_head(a3),d2
	move.w	d2,d3
	rol.w	#QUADRANT_BITS,d3
	and.w	#QUADRANTS-1,d3
	lsr.w	#16-QUADRANT_BITS-8,d2
	btst	#0,d3
	beq	.Angle
	not.b	d2
.Angle	move.b	FlipOf(pc,d3.w),d3
	add.b	#HALF_STEP,d2
	bcs	.Upright
	lsr.b	#1,d2
	move.b	d2,d4
	lsr.b	#1,d4
	add.b	d4,d2
	lsr.b	#5,d2
	and.w	#7,d2
.Done	rts
.Upright
	moveq	#UPRIGHT_FRAME,d2
	rts

; which flipped copy each quadrant uses: 1 = top to bottom, 2 = left to right.
; The frames point left and up: heading right and up they are mirrored, and so on round.
FlipOf:	dc.b	2,0,1,3

;--
; FlightImage
; Which image shows a flight: its kind of enemy, turned the way it is heading.
; In:       a3 = its slot, a5 = state
; Out:      a0 = the image
; Clobbers: d2-d4
FlightImage:
	bsr	FlightFacing
	lsl.w	#8,d2				; FRAME_SIZE each
	lsl.w	#8,d3
	lsl.w	#FLIP_SHIFT-8,d3
	add.w	d3,d2
	moveq	#0,d3
	move.b	fl_obj(a3),d3
	lsr.w	#1,d3
	lea	ObjKind(a5),a0
	move.b	(a0,d3.w),d3
	moveq	#KIND_SHIFT,d4
	lsl.l	d4,d3
	lea	Enemies,a0
	add.l	d3,a0
	add.w	d2,a0
	rts

;--
; FlightPlace
; Where a flight is drawn.
; In:       a0 = its slot, a5 = state
; Out:      d0.w = x in buffer pixels, d1.w = y in buffer rows
; Clobbers: d2-d3, a1-a2
FlightPlace:
	lea	HomeRc(pc),a1
	moveq	#0,d2
	move.b	fl_obj(a0),d2
	add.w	d2,a1				; its row and column in the formation's tables
	moveq	#0,d2
	move.b	(a1)+,d2
	moveq	#0,d3
	move.b	(a1),d3
	moveq	#0,d0
	moveq	#0,d1
	btst	#FLB_LANDED,fl_flags(a0)
	beq	.Flying
	; landed: exactly where the formation will draw it
	lea	HomeX(a5),a2
	move.b	(a2,d3.w),d0
	move.b	(a2,d2.w),d1
	subq.w	#SPRITE_X,d0
	sub.w	#SPRITE_Y,d1
	rts
	; x = position / 128 - 1, 8 bits as in the arcade; row = 312 - position / 128
.Flying	move.w	fl_x(a0),d0
	lsr.w	#POSITION_SHIFT,d0
	move.w	fl_y(a0),d1
	lsr.w	#POSITION_SHIFT,d1
	neg.w	d1
	add.w	#FLIGHT_TOP,d1
	btst	#FLB_HOMING,fl_flags(a0)
	beq	.Free
	; heading home, it aims for where its place was at rest; add how far the formation has moved it
	lea	HomeLoc(a5),a2
	move.b	(a2,d3.w),d3
	add.b	d3,d0
	move.b	(a2,d2.w),d2
	ext.w	d2
	add.w	d2,d1
.Free	and.w	#X_MASK,d0
	subq.w	#SPRITE_X,d0
	rts

	if	STAGE_TEST
	section	bss,bss

; frame, what happened (STAGE_LAUNCHED, FLIGHT_HOME or FLIGHT_GONE), object: 4 bytes an entry
StageLog:
	ds.b	STAGE_LOG_BYTES
	endc
