; Bombs: what the enemies drop on the fighter.
;
; Ported from the arcade (the model is motion/bombs.py). A flying enemy has
; a timer and up to eight chances, a bit each. When the timer runs out the
; next chance is taken: a set bit drops a bomb if the enemy is high enough,
; the fighter is in play and one of the 8 bombs is free. The timer then
; restarts from the stage's value.
;
; A bomb is aimed when it is dropped: its sideways rate is the fighter's
; distance to the side over the height it has to fall, capped. It falls 2
; and 3 lines on alternate arcade frames and moves sideways by rate / 32
; pixels, carrying the remainder. It is gone once it is below the screen,
; which the arcade tests every fourth frame.
;
; Bombs are placed as the arcade's sprite hardware counts, like the shots.
; They are drawn as flyers of half height (flyers.s).

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	BombsDrop
	xdef	BombsFall
	xdef	BombsDraw
	xref	FlightPlace
	xref	BombDraw

MIN_HEIGHT	equ	$4c			; an enemy lower than this (y in two-pixel units) drops nothing
FIGHTER_HALF_Y	equ	SHIP_SY/2+1		; the arcade's constant for the fighter's y, halved: $95
MAX_RATE	equ	$60
RATE_MASK	equ	$7e			; the rate's 32nds
RATEB_LEFT	equ	7
CARRY_MASK	equ	$1f
FIRST_BOMB	equ	$68			; the arcade's object number of the first bomb
SY_MASK		equ	$1ff
STEP_FRAMES	equ	4			; arcade frames between tests for having left the screen
OFF_X		equ	$f4			; a bomb at or past this x,
OFF_TOP		equ	22/2			;   above this y, halved,
OFF_BOTTOM	equ	330/2			;   or at or below this one, is gone
STRESS_WAIT	equ	4			; BOMB_STRESS: arcade frames between an enemy's bombs

	section	code,code

;--
; BombsDrop
; One arcade frame of the enemies' bomb timers: whoever's runs out may drop a bomb.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d4, d6-d7, a0-a3
BombsDrop:
	lea	Flights(a5),a3
	moveq	#FLIGHT_SLOTS-1,d7
.Flight	move.b	fl_flags(a3),d0
	btst	#FLB_ACTIVE,d0
	beq	.Next
	btst	#FLB_PAUSE,d0			; the timer stands while the enemy does
	bne	.Next
	subq.b	#1,fl_wait(a3)
	bne	.Next
	if	BOMB_STRESS
	move.b	#STRESS_WAIT,fl_wait(a3)	; the timing test: every chance is taken, and soon
	else
	move.b	BombReload(a5),fl_wait(a3)
	move.b	fl_chances(a3),d0		; the next chance: the low bit
	lsr.b	#1,d0
	scs	d1
	move.b	d0,fl_chances(a3)
	tst.b	d1
	beq	.Next
	tst.b	InPlay(a5)
	beq	.Next
	cmp.b	#MIN_HEIGHT,fl_y(a3)
	bcs	.Next
	endc
	move.l	a3,a0
	bsr	FlightPlace			; where the enemy is: the bomb starts there
	addq.w	#SPRITE_X,d0
	and.w	#$ff,d0
	add.w	#SPRITE_Y,d1
	and.w	#SY_MASK,d1
	lea	Bombs(a5),a2
	moveq	#0,d6
.Free	tst.w	bm_x(a2)
	beq	.Drop
	addq.l	#bm_SIZEOF,a2
	addq.w	#1,d6
	cmp.w	#BOMBS,d6
	bne	.Free
	bra	.Next
.Drop	move.w	d0,bm_x(a2)
	move.w	d1,bm_y(a2)
	clr.b	bm_carry(a2)
	; rate = (dx * 256 + n) / dy * 5 / 16, at most MAX_RATE, halved, where dx and dy are
	; the distances to the fighter and n is the arcade's leftover: the bomb's object number + 1
	move.w	ShipX(a5),d2
	add.w	#DISPLAY_SX,d2
	moveq	#0,d4
	sub.b	d0,d2
	bcc	.Right
	neg.b	d2
	moveq	#-(1<<RATEB_LEFT),d4		; the fighter is to the left
.Right	lsl.w	#8,d2
	move.w	d6,d0
	add.w	d0,d0
	add.w	#FIRST_BOMB+1,d0
	move.b	d0,d2
	and.l	#$ffff,d2
	lsr.w	#1,d1
	moveq	#FIGHTER_HALF_Y-256,d0
	sub.b	d1,d0
	bcc	.Below
	neg.b	d0
.Below	and.w	#$ff,d0
	bne	.Divide
	move.w	#$ffff,d2			; level with the fighter: as the arcade's division gives
	bra	.Scale
.Divide	divu.w	d0,d2
.Scale	move.w	d2,d0
	lsr.w	#2,d0
	add.w	d2,d0
	lsr.w	#2,d0
	cmp.w	#MAX_RATE,d0
	bls	.Rate
	moveq	#MAX_RATE,d0
.Rate	lsr.w	#1,d0
	or.b	d4,d0
	move.b	d0,bm_rate(a2)
	LOG	#STAGE_BOMB,d0
.Next	lea	fl_SIZEOF(a3),a3
	dbf	d7,.Flight
	rts

;--
; BombsFall
; One arcade frame of the bombs: they fall, and those that have left the screen are freed.
; In:       a5 = state; TickFrame(a5) = the arcade frame this is
; Out:      -
; Clobbers: d0-d5, a0
BombsFall:
	moveq	#1,d4
	and.w	TickFrame(a5),d4
	addq.w	#2,d4				; 2 and 3 lines on alternate frames
	moveq	#STEP_FRAMES-1,d5
	and.w	TickFrame(a5),d5
	lea	Bombs(a5),a0
	moveq	#0,d3				; which bomb
.Bomb	move.w	bm_x(a0),d0
	beq	.Next
	moveq	#RATE_MASK,d1
	and.b	bm_rate(a0),d1
	add.b	bm_carry(a0),d1
	moveq	#CARRY_MASK,d2
	and.b	d1,d2
	move.b	d2,bm_carry(a0)
	lsr.b	#5,d1
	btst	#RATEB_LEFT,bm_rate(a0)
	beq	.Aside
	neg.b	d1
.Aside	add.b	d1,d0
	move.w	d0,bm_x(a0)
	move.w	bm_y(a0),d1
	add.w	d4,d1
	and.w	#SY_MASK,d1
	move.w	d1,bm_y(a0)
	; the arcade looks at bombs 0, 2, 4, 6 on frames 1, 5, 9... and the others on 3, 7, 11...
	moveq	#1,d2
	btst	#0,d3
	beq	.Turn
	moveq	#3,d2
.Turn	cmp.w	d2,d5
	bne	.Next
	cmp.w	#OFF_X,d0
	bcc	.Gone
	lsr.w	#1,d1
	cmp.w	#OFF_TOP,d1
	bcs	.Gone
	cmp.w	#OFF_BOTTOM,d1
	bcs	.Next
.Gone	clr.w	bm_x(a0)
.Next	addq.l	#bm_SIZEOF,a0
	addq.w	#1,d3
	cmp.w	#BOMBS,d3
	bne	.Bomb
	rts

;--
; BombsDraw
; Draw the bombs into the back screen. Call between FlyersBegin and the next other blit.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d4, a0-a3
BombsDraw:
	lea	Bombs(a5),a3
	moveq	#BOMBS-1,d4
.Bomb	move.w	bm_x(a3),d0
	beq	.Next
	subq.w	#SPRITE_X,d0
	move.w	bm_y(a3),d1
	sub.w	#SPRITE_Y,d1
	cmp.w	#LAST_FLYER_X,d0
	bhi	.Next
	cmp.w	#LAST_FLYER_Y,d1
	bhi	.Next
	bsr	BombDraw
.Next	addq.l	#bm_SIZEOF,a3
	dbf	d4,.Bomb
	rts
