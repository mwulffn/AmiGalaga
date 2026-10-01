; Demo: stands in for the player until there is one. It moves the fighter,
; fires and scores. Nothing here is meant to survive.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"

	xdef	DemoFrame

SCORE_FRAMES	equ	8			; the score changes this often
BULLET_SPEED	equ	6
BULLET_START	equ	SHIP_Y-16

	section	code,code

;--
; DemoFrame
; One frame of the demo: move the fighter, its bullets and the score.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1, a0-a1, a3
DemoFrame:
	; the fighter goes from side to side, firing; the score climbs
	lea	DemoShip,a3
	move.w	ShipX(a5),d0
	add.w	(a3),d0
	cmp.w	#SHIP_X_MAX,d0
	bls	.Ship
	neg.w	(a3)
	add.w	(a3),d0
.Ship	move.w	d0,ShipX(a5)
	lea	Bullets(a5),a0
	moveq	#2-1,d1
.Bullet	subq.w	#BULLET_SPEED,2(a0)
	bpl	.Flying
	move.w	d0,(a0)
	move.w	#BULLET_START,2(a0)
.Flying	addq.l	#4,a0
	dbf	d1,.Bullet
	moveq	#SCORE_FRAMES-1,d0
	and.w	FrameCount(a5),d0
	bne	.Scored
	lea	Score+4(a5),a0			; add 30, in decimal
	lea	DemoPoints+4,a1
	sub.w	d0,d0				; clears the extend flag
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
.Scored
	rts

	section	data,data

DemoShip:
	dc.w	2				; the fighter's direction and speed
DemoPoints:
	dc.b	0,0,0,$30
