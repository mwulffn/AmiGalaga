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
	include	"gfx.i"

	xdef	GameInit
	xdef	GameFrame
	xref	StageInit
	xref	StageTick
	xref	FlightStep
	xref	FlyersErase
	xref	FlyersBegin
	xref	FlyerDraw
	xref	FormationCompose
	xref	FormationDraw
	xref	HomeRc
	xref	Enemies
	if	STAGE_TEST
	xdef	StageLog
	endc

STAGE_PAUSE	equ	150			; until there is a game: frames a full formation is shown
UPRIGHT		equ	6*FRAME_SIZE		; an enemy's upright image
FLYING_BITS	equ	1<<FLB_ACTIVE|1<<FLB_LANDED
QUADRANT_BITS	equ	2
QUADRANTS	equ	4
HALF_STEP	equ	21			; half of 15 degrees, where a quadrant is 256
FLIP_SHIFT	equ	11			; FLIP_SIZE as a shift
POSITION_SHIFT	equ	7			; a flight's position to pixels
X_MASK		equ	$ff			; the arcade's sprites have 8 bits of x
FIGHTER_X	equ	17			; from the fighter's left edge to its x as the scripts see it

	section	code,code

;--
; GameInit
; Start at the first stage.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
GameInit:
	clr.w	Clock(a5)
	clr.w	ArcadeFrame(a5)
	clr.w	FlightFrame(a5)
	clr.w	FormNext(a5)
	if	STAGE_TEST
	move.l	#StageLog,StageLogPtr(a5)
	endc
	moveq	#1,d0
	bra	StageInit

;--
; GameFrame
; One displayed frame: launch, fly, land, and draw the playfield into the back screen.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
GameFrame:
	move.w	ShipX(a5),d0
	add.w	#FIGHTER_X,d0
	move.b	d0,FighterX(a5)

	; an arcade frame for each one that begins in this displayed frame
.Tick	move.w	Clock(a5),d6
	cmp.w	#FIFTHS,d6
	bcc	.Ticked
	bsr	StageTick
	sne	d0
	move.b	d0,d7				; zero once every wave is launched
	addq.w	#1,ArcadeFrame(a5)
	addq.w	#FRAME_FIFTHS,Clock(a5)
	bra	.Tick
.Ticked	subq.w	#FIFTHS,Clock(a5)
	move.w	d7,-(sp)

	lea	Flights(a5),a0
	lea	FLIGHT_SLOTS*fl_SIZEOF(a0),a3
.Fly	btst	#FLB_ACTIVE,fl_flags(a0)
	beq	.Flown
	bsr	FlightStep
	if	STAGE_TEST
	tst.w	d0
	beq	.Logged
	move.l	StageLogPtr(a5),a1
	move.w	FlightFrame(a5),(a1)+
	move.b	d0,(a1)+
	move.b	fl_obj(a0),(a1)+
	move.l	a1,StageLogPtr(a5)
.Logged
	endc
	subq.w	#FLIGHT_HOME,d0
	bne	.Flown
	bset	#FLB_LANDED,fl_flags(a0)
.Flown	lea	fl_SIZEOF(a0),a0
	cmp.l	a3,a0
	bne	.Fly
	addq.w	#1,FlightFrame(a5)

	; one row's strip is rebuilt each frame; whoever has landed in that row is in it from now on
	move.w	FormNext(a5),d0
	moveq	#0,d6				; flights in the air or landed
	lea	Flights(a5),a0
	lea	HomeRc(pc),a1
	lea	FormPresent(a5),a2
	moveq	#FLIGHT_SLOTS-1,d1
.Land	moveq	#FLYING_BITS,d2
	and.b	fl_flags(a0),d2
	beq	.Landed
	addq.w	#1,d6
	btst	#FLB_LANDED,d2
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
	move.w	d0,d1
	addq.w	#1,d1
	cmp.w	#FORM_ROWS,d1
	bne	.Next
	moveq	#0,d1
.Next	move.w	d1,FormNext(a5)
	move.w	d6,-(sp)
	bsr	FormationCompose

	bsr	FlyersErase
	bsr	FormationDraw
	bsr	FlyersBegin
	lea	Flights(a5),a3
	moveq	#FLIGHT_SLOTS-1,d7
.Draw	moveq	#FLYING_BITS,d4
	and.b	fl_flags(a3),d4
	beq	.Drawn
	move.l	a3,a0
	bsr	Place
	cmp.w	#LAST_FLYER_X,d0
	bhi	.Drawn
	cmp.w	#LAST_FLYER_Y,d1
	bhi	.Drawn
	bsr	FlightImage
	bsr	FlyerDraw
.Drawn	lea	fl_SIZEOF(a3),a3
	dbf	d7,.Draw
	move.w	(sp)+,d6
	move.w	(sp)+,d7

	; until there is a game: once everyone is in, show the formation a while, then the next stage
	tst.b	d7
	bne	.Busy
	tst.w	d6
	bne	.Busy
	addq.w	#1,StageWait(a5)
	cmp.w	#STAGE_PAUSE,StageWait(a5)
	bne	.Busy
	move.w	Stage(a5),d0
	addq.w	#1,d0
	cmp.w	#DEMO_STAGES,d0
	bls	StageInit
	moveq	#1,d0
	bra	StageInit
.Busy	rts

;--
; FlightImage
; Which image shows a flight: its kind of enemy, turned the way it is heading.
; In:       a3 = its slot, a5 = state
; Out:      a0 = the image
; Clobbers: d2-d4
FlightImage:
	moveq	#0,d2
	move.b	fl_obj(a3),d2
	lsr.w	#1,d2
	lea	ObjKind(a5),a0
	move.b	(a0,d2.w),d2
	moveq	#KIND_SHIFT,d3
	lsl.l	d3,d2
	lea	Enemies,a0
	add.l	d2,a0
	btst	#FLB_LANDED,fl_flags(a3)
	bne	.Upright
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
	lsl.w	#8,d3
	lsl.w	#FLIP_SHIFT-8,d3
	add.w	d3,a0
	add.b	#HALF_STEP,d2
	bcs	.Upright
	lsr.b	#1,d2
	move.b	d2,d4
	lsr.b	#1,d4
	add.b	d4,d2
	lsr.b	#5,d2
	and.w	#7,d2
	lsl.w	#8,d2				; FRAME_SIZE each
	add.w	d2,a0
	rts
.Upright
	lea	UPRIGHT(a0),a0
	rts

; which flipped copy each quadrant uses, in FLIP_SIZE steps: 1 = top to bottom, 2 = left to right.
; The frames point left and up: heading right and up they are mirrored, and so on round.
FlipOf:	dc.b	2,0,1,3

;--
; Place
; Where a flight is drawn.
; In:       a0 = its slot, a5 = state
; Out:      d0.w = x in buffer pixels, d1.w = y in buffer rows
; Clobbers: d2-d3, a1-a2
Place:	lea	HomeRc(pc),a1
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
