; Transform: the enemy that turns into three of something else.
;
; Ported from the arcade (main CPU $1A80; the model is motion/transform.py).
; From stage 4 on, but not on challenging stages, once a stage's waves are
; in and fewer than 10 enemies are left, the first bee in its place (or,
; with no bee, the first butterfly) is picked. It flashes between its own
; colours and those of what it will become for 64 arcade frames, 16 frames
; each; then, if the fighter is in play, it dives as a flagship, a scorpion
; or a spy ship (by stage), and two more split off it on the way (the
; script's spawn command, see flight.s). Shooting all three brings a bonus
; (player.s). One that comes home is its old self again. A stage has one
; transformation at most: if the one picked is shot, or leaves its place,
; while it flashes, there is none.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"
	include	"gfx.i"

	xdef	TransformInit
	xdef	TransformTick
	xdef	TransformHome
	xref	InPlace
	xref	DiveLaunch
	xref	DiveScripts
	xref	HomeRc
	xref	Flash

FIRST_STAGE_WITH equ	3			; no transformation before this stage (itself a challenging one)
CHALLENGE_MASK	equ	3			; a stage whose number ends in these two bits set is a challenging stage
FEW_LEFT	equ	10			; one is picked once fewer than this many enemies are left
FLASH_START	equ	$c0			; TransformTimer: where it starts,
FLASH_END	equ	$ff			;   where it stops,
FLASH_WAIT	equ	$e0			;   and where it is put back to if the fighter is not in play then
FLASHB_NEW	equ	4			;   this bit set: it shows its new colours
BEES		equ	$08			; the objects it is picked from: the bees,
BEES_END	equ	$30
BUTTERFLIES	equ	$40			;   then the butterflies
BUTTERFLIES_END	equ	$60
KINDS		equ	3			; what it becomes: (stage / 4) mod this, from KIND_GALAXIAN
TRIO		equ	3
SCRIPT_TRIOS	equ	16			; in DiveScripts: the three kinds' dives
MIRROR_BIT	equ	2			; an object with this bit set is on the right, and flies mirrored
NOBODY		equ	$ff			; Special: nobody is picked

	section	code,code

;--
; TransformInit
; A new stage: nobody picked, the stage's one transformation still to come.
; In:       a5 = state
; Out:      -
; Clobbers: -
TransformInit:
	clr.b	TransformDone(a5)
	clr.b	TransformTimer(a5)
	clr.b	TrioLeft(a5)
	move.b	#NOBODY,Special(a5)
	move.l	#Flash,FlashImage(a5)
	rts

;--
; TransformTick
; One arcade frame: pick an enemy, let it flash, send it off.
; In:       d6.w = when in this displayed frame the arcade frame begins, in fifths,
;           a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a1
TransformTick:
	tst.b	WavesIn(a5)
	beq	.Done
	tst.b	TransformDone(a5)
	bne	.Done
	moveq	#0,d0
	move.w	Stage(a5),d0
	cmp.w	#FIRST_STAGE_WITH,d0
	bcs	.Done
	moveq	#CHALLENGE_MASK,d1
	and.w	d0,d1
	subq.w	#CHALLENGE_MASK,d1
	beq	.Done
	cmp.b	#FEW_LEFT,Alive(a5)
	bcc	.Done
	moveq	#0,d4
	move.b	TransformTimer(a5),d5
	bne	.Picked
	; the first bee in its place, or else the first butterfly
	moveq	#BEES,d4
.Bee	bsr	InPlace
	bne	.Pick
	addq.w	#2,d4
	cmp.w	#BEES_END,d4
	bne	.Bee
	moveq	#BUTTERFLIES,d4
.Butterfly
	bsr	InPlace
	bne	.Pick
	addq.w	#2,d4
	cmp.w	#BUTTERFLIES_END,d4
	bne	.Butterfly
.Done	rts
.Pick	move.b	#FLASH_START,TransformTimer(a5)
	move.b	d4,Special(a5)
	lea	ObjKind(a5),a0
	move.w	d4,d0
	lsr.w	#1,d0
	move.b	(a0,d0.w),SpecialKind(a5)
	; kind = KIND_GALAXIAN + (stage / 4) mod 3
	moveq	#0,d0
	move.w	Stage(a5),d0
	lsr.w	#2,d0
	divu.w	#KINDS,d0
	swap	d0
	move.w	d0,d1
	addq.w	#KIND_GALAXIAN,d1
	move.b	d1,TransformKind(a5)
	; its own shape in that kind's colours, to flash with
	mulu.w	#FLASH_SET,d0
	cmp.w	#BUTTERFLIES,d4
	bcs	.Shape
	add.w	#FLASH_SHAPE,d0
.Shape	add.l	#Flash,d0
	move.l	d0,FlashImage(a5)
	SOUND	SND_TRANSFORM
	rts

.Picked	move.b	Special(a5),d4
	cmp.b	#FLASH_END,d5
	beq	.Ready
	addq.b	#1,d5
	move.b	d5,TransformTimer(a5)
	bsr	InPlace
	beq	.Lost
	btst	#FLASHB_NEW,d5
	sne	d2
	bra	FlashShow
.Lost	st	TransformDone(a5)		; shot, or gone diving: no transformation this stage
	moveq	#0,d2
	bra	FlashShow
	; the flashing is over: it goes, if the fighter is there to see it
.Ready	tst.b	InPlay(a5)
	bne	.Go
	move.b	#FLASH_WAIT,TransformTimer(a5)
	rts
.Go	st	TransformDone(a5)
	moveq	#0,d2
	bsr	FlashShow
	bsr	InPlace
	beq	.Done
	lea	Flights(a5),a0			; and if there is a flight free for it
	moveq	#FLIGHT_SLOTS-1,d0
.Slot	moveq	#1<<FLB_ACTIVE|1<<FLB_LANDED,d1
	and.b	fl_flags(a0),d1
	beq	.Launch
	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Slot
	rts
.Launch	lea	ObjKind(a5),a0
	move.w	d4,d0
	lsr.w	#1,d0
	move.b	TransformKind(a5),(a0,d0.w)
	move.b	#TRIO,TrioLeft(a5)
	moveq	#0,d0
	move.b	TransformKind(a5),d0
	subq.w	#KIND_GALAXIAN,d0
	add.w	d0,d0
	lea	DiveScripts+SCRIPT_TRIOS(pc),a0
	move.w	(a0,d0.w),d0
	moveq	#MIRROR_BIT,d5
	and.w	d4,d5
	bra	DiveLaunch

;--
; FlashShow
; Show the picked enemy in its own colours or in its new ones, in its row's strip.
; In:       d4.w = its object, d2.b = nonzero for the new ones, a5 = state
; Out:      -
; Clobbers: d0-d1, d3, a0
FlashShow:
	lea	HomeRc(pc),a0
	moveq	#0,d0
	move.b	(a0,d4.w),d0
	moveq	#0,d1
	move.b	1(a0,d4.w),d1
	lsr.w	#1,d1				; its column
	sub.w	#HOME_ROWS+2*STRIP_ROWS,d0	; its row, doubled
	lea	FormAlt(a5),a0
	move.w	(a0,d0.w),d3
	tst.b	d2
	beq	.Own
	bset	d1,d3
	bne	.Same
	bra	.Changed
.Own	bclr	d1,d3
	beq	.Same
.Changed
	move.w	d3,(a0,d0.w)
	lsr.w	#1,d0
	bset	d0,FormDirty(a5)		; its strip is rebuilt at once
.Same	rts

;--
; TransformHome
; The one that transformed is back in its place: it is what it was.
; In:       a5 = state
; Out:      -
; Clobbers: d0, a1
TransformHome:
	moveq	#0,d0
	move.b	Special(a5),d0
	lsr.w	#1,d0
	lea	ObjKind(a5),a1
	move.b	SpecialKind(a5),(a1,d0.w)
	move.b	#NOBODY,Special(a5)
	rts
