; Demo: stands in for the game until there is one. It moves things so the
; display code has something to draw and the timing has something to measure.
; Nothing here is meant to survive.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"sound.i"
	include	"state.i"
	include	"gfx.i"

	xdef	DemoFrame
	xref	FlyersErase
	xref	FlyersBegin
	xref	FlyerDraw
	xref	FormationCompose
	xref	FormationDraw
	xref	Enemies

; a demo flyer
	rsreset
df_x		rs.w	1
df_y		rs.w	1
df_dx		rs.w	1
df_dy		rs.w	1
df_image	rs.l	2		; wings open, wings closed
df_SIZEOF	rs.b	0

X_RANGE		equ	GUARD+PLAY_WIDTH-1	; fully hidden at the left to fully in the gap
Y_RANGE		equ	GUARD+DISPLAY_LINES	; fully hidden above to fully hidden below
FLAP_FRAMES	equ	16
BREATHE_FRAMES	equ	8			; the formation's spread changes this often

	section	code,code

;--
; DemoFrame
; One frame of the demo: bounce the flyers around and draw them.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
DemoFrame:
	; the formation sways every frame and breathes every eighth; one strip is rebuilt a frame
	lea	DemoForm,a3
	move.w	FormSway(a5),d0
	add.w	(a3),d0
	cmp.w	#FORM_SWAY,d0
	bls	.Sway
	neg.w	(a3)
	add.w	(a3),d0
.Sway	move.w	d0,FormSway(a5)
	moveq	#BREATHE_FRAMES-1,d0
	and.w	FrameCount(a5),d0
	bne	.Breathed
	move.w	FormSpread(a5),d0
	add.w	2(a3),d0
	cmp.w	#FORM_SPREAD_MAX,d0
	bls	.Spread
	neg.w	2(a3)
	add.w	2(a3),d0
.Spread	move.w	d0,FormSpread(a5)
.Breathed
	move.w	4(a3),d0
	addq.w	#1,d0
	cmp.w	#FORM_ROWS,d0
	bne	.Row
	moveq	#0,d0
.Row	move.w	d0,4(a3)
	bsr	FormationCompose

	bsr	FlyersErase
	bsr	FormationDraw
	if	DEMO_FLYERS
	bsr	FlyersBegin
	moveq	#0,d6				; which of the two images: 0 or 4
	move.w	FrameCount(a5),d0
	and.w	#FLAP_FRAMES,d0
	beq	.Open
	moveq	#4,d6
.Open	lea	DemoFlyers,a3
	moveq	#DEMO_FLYERS-1,d7
.Flyer	movem.w	df_x(a3),d0-d1/d4-d5		; x, y, dx, dy
	add.w	d4,d0
	cmp.w	#X_RANGE,d0
	bls	.XOk
	neg.w	d4
	add.w	d4,d0
.XOk	add.w	d5,d1
	cmp.w	#Y_RANGE,d1
	bls	.YOk
	neg.w	d5
	add.w	d5,d1
.YOk	movem.w	d0-d1/d4-d5,df_x(a3)
	move.l	df_image(a3,d6.w),a0
	bsr	FlyerDraw
	lea	df_SIZEOF(a3),a3
	dbf	d7,.Flyer
	endc
	rts

	section	data,data

; Starting positions and speeds from a small generator, so any count works.
Seed	set	$2c7b
NEXT	macro
Seed	set	(Seed*25173+13849)&$ffff
	endm

; \1 = GFX_ name, \2 = its wings-open frame, \3 = wings-closed frame
FLYER	macro
	NEXT
	dc.w	(Seed>>4)//(X_RANGE+1)
	NEXT
	dc.w	(Seed>>4)//(Y_RANGE+1)
	NEXT
	dc.w	(1+(Seed>>5)//3)*(1-((Seed>>12)&2))	; dx: 1 to 3 either way
	NEXT
	dc.w	(1+(Seed>>5)//2)*(1-((Seed>>12)&2))	; dy: 1 or 2 either way
	dc.l	Enemies+\1+\2*FRAME_SIZE,Enemies+\1+\3*FRAME_SIZE
	endm

DemoForm:
	dc.w	1,1,0				; sway direction, spread direction, next row to rebuild

DemoFlyers:
	rept	(DEMO_FLYERS+9)/10
	FLYER	GFX_BOSS,6,7
	FLYER	GFX_BUTTERFLY,6,7
	FLYER	GFX_BEE,6,7
	FLYER	GFX_BOSSHIT,6,7
	FLYER	GFX_SCORPION,6,6
	FLYER	GFX_BOSCONIAN,6,6
	FLYER	GFX_GALAXIAN,6,6
	FLYER	GFX_DRAGONFLY,6,6
	FLYER	GFX_SATELLITE,6,6
	FLYER	GFX_ENTERPRISE,6,6
	endr
