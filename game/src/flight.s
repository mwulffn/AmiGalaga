; Flight: enemies flying the arcade's scripts.
;
; A port of motion/pal_scale.py. A flying enemy has a position, a
; heading and a script: steps of (speed, turn rate, frames) and commands
; such as jump, "head for my place in the formation" and "dive to this
; depth". Each frame the heading turns by the turn rate and the enemy
; moves `speed` along the nearer axis and a fraction of it along the
; other, which is what gives Galaga's paths their shape.
;
; Time is counted in fifths of an arcade frame (see flight.i), so the
; same code runs at the arcade's speed on a 50 Hz display, or exactly as
; the arcade does when built with EXACT_TIMING. A step that ends part-way
; through a displayed frame gives it only its share of turn and distance.
;
; The scripts and tables are built from the user's ROM by motion/extract.py.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"

	xdef	FlightLaunch
	xdef	FlightStep
	xdef	FlightTurn
	xdef	MotionScripts
	xdef	EntryPaths
	xdef	StartPos
	xdef	StageIndex
	xdef	ChallengeIndex
	xdef	StageData
	xdef	ChallengeData
	xdef	WaveObjects
	xdef	HomeRc
	xdef	BreathePatterns
	xdef	DiveScripts
	xdef	EntryBombers
	xdef	StageConfig
	xdef	BombFlagTable
	xdef	BossReload
	xdef	ButterflyReload
	xdef	BeeReload

FIRST_COMMAND	equ	$ef			; script bytes from here up are commands
COMMANDS	equ	$100-FIRST_COMMAND
REST_FRAMES	equ	256			; a step with 0 frames lasts this many
SPEED_MASK	equ	15
HOME_REACH	equ	2-EXACT_TIMING		; how close counts as home, in two-pixel units
HEADING_SHIFT	equ	22			; the arcade's 10-bit heading to ours
QUARTER_TURN	equ	$100			; in the arcade's heading
TOP_OF_SCREEN	equ	$9c			; y, in two-pixel units, just above the screen
HOME_ROW_ABOVE	equ	$20			; "home row" flights start this far above their row
TRANSIENT_MASK	equ	$38			; objects $38-$3f only fly through
PLACED		equ	$60			; objects below this have a place in the formation
AIM_TABLE	equ	8			; an aim command is followed by this many step lengths
CAPTURE_Y	equ	$48			; where a capturing boss stops, in two-pixel units
FRAC_BITS	equ	7			; a position's fraction, and a heading's fraction of an octant
FRAC_MASK	equ	$7f

	section	code,code

;--
; FlightLaunch
; Start a flight. The first FlightStep reads its script's first token.
; In:       a0 = the flight's slot, d0.w = script (offset into MotionScripts),
;           d1.b = y, d2.b = x (two-pixel units), d3.b = heading (quarter turns),
;           d4.b = object, d5.b = nonzero to fly it mirrored,
;           d6.w = fifths of an arcade frame to wait first: 0, or when in this
;           displayed frame the arcade frame that launches it begins
; Out:      -
; Clobbers: d1-d3
FlightLaunch:
	move.w	d0,fl_script(a0)
	move.w	d6,fl_left(a0)
	lsl.w	#8,d1
	move.w	d1,fl_y(a0)
	lsl.w	#8,d2
	move.w	d2,fl_x(a0)
	and.l	#$ff,d3
	swap	d3
	lsl.l	#8,d3
	lsl.l	#HEADING_SHIFT-16,d3		; quarter turns to the top two bits
	move.l	d3,fl_head(a0)
	move.b	d4,fl_obj(a0)
	move.b	#1<<FLB_ACTIVE|1<<FLB_PAUSE,fl_flags(a0)
	clr.b	fl_chances(a0)			; whoever launches it says if it bombs
	tst.b	d5
	beq	.Plain
	bset	#FLB_MIRROR,fl_flags(a0)
.Plain	clr.w	fl_yo(a0)
	rts

;--
; FlightStep
; Advance one flight by one displayed frame.
; In:       a0 = its slot, a5 = state
; Out:      d0 = FLIGHT_FLYING, FLIGHT_HOME or FLIGHT_GONE
; Clobbers: d1-d7, a1-a2
FlightStep:
	move.l	fl_head(a0),d4			; the heading it moves along this frame
	cmp.w	#FIFTHS,fl_left(a0)
	bcs	.Shared
	; the whole frame belongs to the current step
	subq.w	#FIFTHS,fl_left(a0)
	btst	#FLB_PAUSE,fl_flags(a0)
	bne	.Still
	move.l	fl_turn(a0),d6
	moveq	#1,d0
	and.w	FlightFrame(a5),d0
	add.w	d0,d0
	move.w	fl_dist(a0,d0.w),d5
	bra	.Checks

	; a step ends inside this frame: each step gives its share
.Shared	moveq	#FIFTHS,d7			; fifths still to hand out
	moveq	#0,d6				; turn
	moveq	#0,d5				; distance
.Share	tst.w	fl_left(a0)
	bne	.Have
	bsr	LoadStep
	beq	.Gone
	cmp.l	fl_head(a0),d4
	beq	.Have
	moveq	#0,d6				; the script set the heading: the old step's turn is void
	move.l	fl_head(a0),d4
.Have	move.w	fl_left(a0),d0
	cmp.w	d7,d0
	bls	.Take
	move.w	d7,d0
.Take	sub.w	d0,fl_left(a0)
	sub.w	d0,d7
	btst	#FLB_PAUSE,fl_flags(a0)
	bne	.Shared1
	; turn += rate * TurnTable[k] << 8, distance += DistTable[k][speed]
	move.w	d0,d1
	add.w	d1,d1
	lea	TurnTable(pc),a1
	move.w	(a1,d1.w),d2
	move.b	fl_rate(a0),d3
	ext.w	d3
	muls.w	d3,d2
	lsl.l	#8,d2
	add.l	d2,d6
	moveq	#0,d2
	move.b	fl_hi(a0),d2
	btst	#0,FlightFrame+1(a5)
	beq	.Even
	move.b	fl_lo(a0),d2
.Even	lsl.w	#4,d0				; DistTable: 16 speeds per k
	add.w	d0,d2
	add.w	d2,d2
	lea	DistTable(pc),a1
	add.w	(a1,d2.w),d5
.Shared1
	tst.w	d7
	bne	.Share
	btst	#FLB_PAUSE,fl_flags(a0)
	beq	.Checks
.Still	moveq	#FLIGHT_FLYING,d0
	rts
.Gone	moveq	#FLIGHT_GONE,d0
	rts

.Checks	move.b	fl_y(a0),d0			; whole two-pixel units
	move.b	fl_x(a0),d1
	btst	#FLB_HOMING,fl_flags(a0)
	beq	.NotHome
	; home when within HOME_REACH on both axes
	move.b	d0,d2
	sub.b	fl_ty(a0),d2
	bpl	.DyAbs
	neg.b	d2
.DyAbs	cmp.b	#HOME_REACH,d2
	bhi	.NotHome
	move.b	d1,d2
	sub.b	fl_tx(a0),d2
	bpl	.DxAbs
	neg.b	d2
.DxAbs	cmp.b	#HOME_REACH,d2
	bhi	.NotHome
	bclr	#FLB_ACTIVE,fl_flags(a0)
	clr.w	fl_y(a0)
	move.b	fl_ty(a0),fl_y(a0)
	clr.w	fl_x(a0)
	move.b	fl_tx(a0),fl_x(a0)
	moveq	#FLIGHT_HOME,d0
	rts
.NotHome
	btst	#FLB_DIVING,fl_flags(a0)
	beq	.Move
	; the dive's depth is reached at the target or one unit below it;
	; at 1.2 frames a step it can also be passed without being seen there
	sub.b	fl_ty(a0),d0
	beq	.Deep
	if	EXACT_TIMING
	addq.b	#1,d0
	bne	.Move
	else
	bpl	.Move
	endc
.Deep	clr.w	fl_left(a0)			; the next step starts next frame
	bclr	#FLB_DIVING,fl_flags(a0)

.Move	tst.w	d5
	beq	.Turn
	; octant = top 3 bits of the heading, fraction = the next 7, reversed in odd octants
	; along = distance, negative in octants 3-6; across = distance * fraction / 128,
	; negative in octants 0, 1, 6, 7 ... as (octant ^ 2) - 1 has bit 2 set
	; y is the dominant axis in octants 1, 2, 5, 6
	move.l	d4,d0
	swap	d0
	move.w	d0,d1
	lsr.w	#16-3-FRAC_BITS,d1
	and.w	#FRAC_MASK,d1			; fraction
	rol.w	#3,d0
	and.w	#7,d0				; octant
	btst	#0,d0
	beq	.Frac
	eor.w	#FRAC_MASK,d1
.Frac	mulu.w	d5,d1
	lsr.l	#FRAC_BITS,d1			; across
	move.w	d0,d2
	eor.w	#2,d2
	subq.w	#1,d2
	btst	#2,d2
	beq	.Across
	neg.w	d1
.Across	move.w	d0,d2
	addq.w	#1,d2
	btst	#2,d2
	beq	.Along
	neg.w	d5
.Along	btst	#1,d2
	beq	.XMain
	add.w	d5,fl_y(a0)
	add.w	d1,fl_x(a0)
	bra	.Turn
.XMain	add.w	d5,fl_x(a0)
	add.w	d1,fl_y(a0)
.Turn	add.l	d6,fl_head(a0)
	moveq	#FLIGHT_FLYING,d0
	rts

;--
; LoadStep
; Run script tokens until one takes time.
; In:       a0 = the flight's slot, a5 = state
; Out:      d0 = nonzero if the flight goes on, Z = its script ended
; Clobbers: d1-d3, a1-a2
LoadStep:
	lea	MotionScripts(pc),a1
	add.w	fl_script(a0),a1
.Token	moveq	#0,d0
	move.b	(a1),d0
	cmp.b	#FIRST_COMMAND,d0
	bcc	.Command
	; a plain step: two speeds, a turn rate, a number of frames
	move.b	d0,d1
	and.b	#SPEED_MASK,d1
	move.b	d1,fl_lo(a0)
	lsr.b	#4,d0
	move.b	d0,fl_hi(a0)
	move.b	1(a1),d0
	btst	#FLB_MIRROR,fl_flags(a0)
	beq	.Rate
	neg.b	d0
.Rate	move.b	d0,fl_rate(a0)
	moveq	#0,d0
	move.b	2(a1),d0
	addq.l	#3,a1
	bsr	Precompute
	bra	.Frames

.Command
	not.b	d0				; $ff is command 0, $fe command 1, ...
	add.w	d0,d0
	move.w	.Table(pc,d0.w),d0
	jmp	.Table(pc,d0.w)			; lint: targets .End, .AimAtFighter, .Jump, .DiveTo, .GoHome, .JumpUnlessLastStand, .ColumnX, .WrapToTop, .JumpIfTransient, .SetHeading, .BecomeFlyer, .AimCapture, .AimRed, .SpawnEscort, .HomeRowY, .JumpIfHard, .JumpIfHarder
.Table	dc.w	.End-.Table,.AimAtFighter-.Table,.Jump-.Table,.DiveTo-.Table
	dc.w	.GoHome-.Table,.JumpUnlessLastStand-.Table,.ColumnX-.Table,.WrapToTop-.Table
	dc.w	.JumpIfTransient-.Table,.SetHeading-.Table,.BecomeFlyer-.Table,.AimCapture-.Table
	dc.w	.AimRed-.Table,.SpawnEscort-.Table,.HomeRowY-.Table,.JumpIfHard-.Table
	dc.w	.JumpIfHarder-.Table

.End	bclr	#FLB_ACTIVE,fl_flags(a0)
	moveq	#0,d0
	rts

	; this step's length comes from a table of 8, by where the fighter is
.AimAtFighter
	moveq	#0,d0
	move.b	FighterX(a5),d0
	bne	.HaveX
	move.w	#$80,d0
.HaveX	btst	#FLB_MIRROR,fl_flags(a0)
	bne	.Sided
	neg.b	d0
	add.b	#$f2,d0
.Sided	add.b	#$0e,d0
	divu.w	#30,d0
	bra	.Aimed
.AimRed	moveq	#0,d0
	move.b	FighterX(a5),d0
	cmp.b	#$1e,d0
	bcc	.NotLow
	moveq	#$1e,d0
.NotLow	cmp.b	#$d1,d0
	bls	.NotHigh
	move.w	#$d1,d0
.NotHigh
	lsr.w	#1,d0
	moveq	#0,d1
	move.b	fl_x(a0),d1
	sub.w	d1,d0				; fighter - enemy, halved again below with its sign kept
	move.w	d0,d1
	and.w	#$ff,d0
	lsr.w	#1,d0
	tst.w	d1
	bpl	.Positive
	or.b	#$80,d0
.Positive
	btst	#FLB_MIRROR,fl_flags(a0)
	beq	.Unmirrored
	neg.b	d0
.Unmirrored
	add.b	#$18,d0
	bpl	.InRange
	moveq	#0,d0
.InRange
	cmp.b	#$2f,d0
	bls	.Capped
	moveq	#$2f,d0
.Capped	and.w	#$ff,d0
	divu.w	#6,d0
	addq.w	#1,d0
.Aimed	and.w	#$ff,d0				; the index into the table that follows
	move.b	(a1,d0.w),d0
	lea	1+AIM_TABLE(a1),a1
	bra	.Frames

.Jump	bsr	Target
	bra	.Token

.DiveTo	move.b	1(a1),fl_ty(a0)
	bset	#FLB_DIVING,fl_flags(a0)
	addq.l	#2,a1
	moveq	#0,d0				; lasts until the depth is reached
	bra	.Frames

.GoHome	bsr	HomeIndex
	; step sideways by the formation's offset now, so that it can be added
	; back while it flies home and the formation moves; then aim at its place
	move.b	(a2,d1.w),d0			; column: offset
	move.b	d0,fl_xo(a0)
	ext.w	d0
	lsl.w	#FRAC_BITS,d0
	sub.w	d0,fl_x(a0)
	move.b	(a2,d2.w),d0			; row: offset
	move.b	d0,fl_yo(a0)
	ext.w	d0
	lsl.w	#FRAC_BITS,d0
	add.w	d0,fl_y(a0)
	move.b	1(a2,d2.w),d0			; row: origin
	move.b	1(a2,d1.w),d1			; column: origin
	lsr.b	#1,d1
	move.b	d0,fl_ty(a0)
	move.b	d1,fl_tx(a0)
	bsr	HeadFor
	bset	#FLB_HOMING,fl_flags(a0)
	addq.l	#1,a1
	bra	.Token

.JumpUnlessLastStand
	move.b	BossKilled(a5),d0
	subq.b	#1,d0
	and.b	LastStand(a5),d0
	beq	.Jump
.Skip	addq.l	#3,a1
	bra	.Token

.JumpIfTransient
	moveq	#TRANSIENT_MASK,d0
	and.b	fl_obj(a0),d0
	cmp.b	#TRANSIENT_MASK,d0
	beq	.Jump
	bra	.Skip

.ColumnX
	bsr	HomeIndex
	lea	HomeX(a5),a2
	move.b	(a2,d1.w),d0
	lsr.b	#1,d0
	move.b	d0,fl_x(a0)
	addq.l	#1,a1
	bra	.Wait

.WrapToTop
	move.b	#TOP_OF_SCREEN,fl_y(a0)
	addq.l	#1,a1
	bra	.Wait

.HomeRowY
	bsr	HomeIndex
	move.b	1(a2,d2.w),d0
	add.b	#HOME_ROW_ABOVE,d0
	move.b	d0,fl_y(a0)
	addq.l	#1,a1
	bra	.Wait

.SetHeading
	move.b	1(a1),d0			; in 256ths of a turn
	btst	#FLB_MIRROR,fl_flags(a0)
	beq	.Heading
	add.b	#$80,d0
	neg.b	d0
.Heading
	clr.l	fl_head(a0)
	move.b	d0,fl_head(a0)
	move.b	#DIVE_WAIT,fl_wait(a0)		; and a new set of chances to bomb
	move.b	BombFlags(a5),fl_chances(a0)
	addq.l	#2,a1
	bra	.Wait

.JumpIfHard
	tst.b	StageHard(a5)
	bra	.Branch
.JumpIfHarder
	tst.b	StageHarder(a5)
.Branch	beq	.Stay
	bsr	Target
	bra	.Wait
.Stay	addq.l	#3,a1
	; these commands stand still for one arcade frame
.Wait	bset	#FLB_PAUSE,fl_flags(a0)
	move.w	#FRAME_FIFTHS,fl_left(a0)
	bra	.Loaded

.BecomeFlyer
	addq.l	#1,a1
	bra	.Token

.AimCapture
	moveq	#0,d1
	move.b	FighterX(a5),d1
	addq.w	#3,d1
	and.w	#$f8,d1
	addq.w	#1,d1
	cmp.w	#$29,d1
	bcc	.NotLeft
	moveq	#$29,d1
.NotLeft
	cmp.w	#$ca,d1
	bcs	.NotRight
	move.w	#$c9,d1
.NotRight
	move.b	d1,BeamColumn(a5)		; the beam will come down here; from now the game
	clr.b	BeamStep(a5)			; watches this boss (capture.s)
	st	ApproachOn(a5)
	move.l	a0,CaptureSlot(a5)
	lsr.w	#1,d1
	moveq	#CAPTURE_Y,d0
	bsr	HeadFor
	addq.l	#1,a1
	bra	.Token

.SpawnEscort
	addq.l	#3,a1				; the escort itself is the game's business
	bra	.Token

	; d0 = frames for a moving step
.Frames	tst.w	d0
	bne	.Count
	move.w	#REST_FRAMES,d0
.Count	mulu.w	#FRAME_FIFTHS,d0
	move.w	d0,fl_left(a0)
	bclr	#FLB_PAUSE,fl_flags(a0)
.Loaded	sub.l	#MotionScripts,a1
	move.w	a1,fl_script(a0)
	moveq	#1,d0
	rts

;--
; Target
; Follow a jump: the two bytes after the command are an offset into the scripts.
; In:       a1 = the command
; Out:      a1 = where it points
; Clobbers: d0
Target:	move.b	1(a1),d0
	lsl.w	#8,d0
	move.b	2(a1),d0
	lea	MotionScripts(pc),a1
	add.w	d0,a1
	rts

;--
; HomeIndex
; Find a flight's row and column in the formation's tables.
; In:       a0 = the flight's slot, a5 = state
; Out:      d1.w = column index, d2.w = row index, a2 = HomeLoc
; Clobbers: d0
HomeIndex:
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d0
	move.b	fl_obj(a0),d0
	cmp.b	#PLACED,d0
	bcc	.None
	lea	HomeRc(pc),a2
	move.b	(a2,d0.w),d2
	move.b	1(a2,d0.w),d1
.None	lea	HomeLoc(a5),a2
	rts

;--
; Precompute
; Work out a step's turn and distances for a whole displayed frame.
; In:       a0 = the flight's slot, with fl_rate, fl_lo and fl_hi set
; Out:      -
; Clobbers: d1, a2
Precompute:
	move.b	fl_rate(a0),d1
	ext.w	d1
	muls.w	#(2*FIFTHS*16384+5)/10,d1
	lsl.l	#8,d1
	move.l	d1,fl_turn(a0)
	lea	DistTable+FIFTHS*16*2(pc),a2
	moveq	#0,d1
	move.b	fl_hi(a0),d1
	add.w	d1,d1
	move.w	(a2,d1.w),fl_dist(a0)
	moveq	#0,d1
	move.b	fl_lo(a0),d1
	add.w	d1,d1
	move.w	(a2,d1.w),fl_dist+2(a0)
	rts

;--
; FlightTurn
; Change a flight's turn rate in mid step.
; In:       a0 = the flight's slot, d0.b = the rate (as flown: not mirrored again)
; Out:      -
; Clobbers: d1, a2
FlightTurn:
	move.b	d0,fl_rate(a0)
	bra	Precompute

;--
; HeadFor
; Point a flight at a place, the way the arcade works the heading out.
; In:       a0 = the flight's slot, d0.b = y, d1.b = x of the place, in two-pixel units
; Out:      -
; Clobbers: d0-d3
HeadFor:
	; b collects the octant: bit 0 = to the left, bit 1 = below;
	; then the smaller of |dx|, |dy| over the larger gives the angle within it
	moveq	#0,d3				; b
	move.b	fl_x(a0),d2
	sub.b	d2,d1				; dx = tx - x
	bcc	.DxOk
	moveq	#1,d3
	neg.b	d1
.DxOk	move.b	fl_y(a0),d2
	sub.b	d2,d0				; dy = ty - y
	bcc	.DyOk
	eor.b	#1,d3
	or.b	#2,d3
	neg.b	d0
.DyOk	and.w	#$ff,d0				; a = |dy|
	and.w	#$ff,d1				; c = |dx|
	; less = a < c; t = (a << 1 | less) ^ b; b = b << 1 | (t's low bit clear)
	moveq	#0,d2
	cmp.w	d1,d0
	bcc	.NotLess
	moveq	#1,d2
	exg	d0,d1				; a is the larger from here
.NotLess
	eor.b	d3,d2				; t's low bit = less ^ b's low bit
	add.b	d3,d3
	btst	#0,d2
	bne	.TSet
	addq.b	#1,d3
.TSet	; quotient = (c << 8) / a; all ones if a is 0, as the arcade's routine gives
	lsl.w	#8,d1
	tst.w	d0
	bne	.Divide
	move.w	#$ffff,d1
	bra	.Quotient
.Divide	divu.w	d0,d1
.Quotient
	move.w	d1,d0
	lsr.w	#8,d0
	eor.b	d3,d0
	btst	#0,d0
	beq	.Low
	not.b	d1
.Low	; arcade heading = (b << 8 | low byte) >> 1, a 10-bit value
	and.w	#$ff,d1
	lsl.w	#8,d3
	or.w	d3,d1
	lsr.w	#1,d1
	and.l	#$3ff,d1
	swap	d1
	lsl.l	#HEADING_SHIFT-16,d1
	move.l	d1,fl_head(a0)
	rts

; heading added per unit of turn rate in k fifths of an arcade frame, to be shifted left 8
TurnTable:
K	set	0
	rept	7
	dc.w	(2*K*16384+5)/10
K	set	K+1
	endr

; distance in 1/128 pixel at speeds 0-15 over k fifths of an arcade frame
DistTable:
K	set	0
	rept	7
V	set	0
	rept	16
	dc.w	(2*V*K*128+5)/10
V	set	V+1
	endr
K	set	K+1
	endr

	include	"motion_data.s"
