; Video: the display, its two screen buffers, and the vertical blank.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"sound.i"
	include	"state.i"

	xdef	VideoInit
	xdef	VideoWaitFrame
	xdef	VideoFlip
	xref	State

; display window: 320 x 256 low resolution, PAL
DIW_START	equ	$2c81
DIW_STOP	equ	$2cc1
DDF_START	equ	$0038
DDF_STOP	equ	$00d0
BPLCON0_4PLANES	equ	$4200		; 4 bitplanes, colour burst on
PRIORITY	equ	$001b		; sprites 0-5 in front of the bitplanes, 6-7 behind
COPPER_END	equ	$fffffffe

	section	code,code

;--
; VideoInit
; Clear both screens, show the first, start the display and the vertical blank interrupt.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d1, a0-a1
VideoInit:
	lea	Screens,a0
	move.w	#2*SCREEN_SIZE/4-1,d0
.Clear	clr.l	(a0)+
	dbf	d0,.Clear
	move.l	#Screen1,FrontBuffer(a5)
	move.l	#Screen2,BackBuffer(a5)
	bsr	ShowFront

	lea	CopperSprites+2,a0	; every sprite starts on the empty one
	move.l	#NullSprite,d0
	moveq	#8-1,d1
.Sprite	swap	d0
	move.w	d0,(a0)
	swap	d0
	move.w	d0,4(a0)
	addq.l	#8,a0
	dbf	d1,.Sprite

	lea	VBlank(pc),a0
	move.l	a0,VEC_LEVEL3.w
	move.l	#Copper,cop1lc(a6)
	move.w	d0,copjmp1(a6)
	move.w	#DMA_SET|DMA_MASTER|DMA_BITPLANE|DMA_COPPER|DMA_BLITTER|DMA_SPRITE|(BLITTER_PRIORITY*DMA_BLTPRI),dmacon(a6)
	move.w	#INT_VERTB,intreq(a6)
	move.w	#INT_SET|INT_MASTER|INT_VERTB,intena(a6)
	rts

;--
; VideoWaitFrame
; Wait for the next vertical blank.
; In:       a5 = state
; Out:      -
; Clobbers: d0
VideoWaitFrame:
	move.w	FrameCount(a5),d0
.Wait	cmp.w	FrameCount(a5),d0
	beq	.Wait
	rts

;--
; VideoFlip
; Show the back buffer from the next frame on, and make the old front buffer the one to draw into.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0
VideoFlip:
	move.l	BackBuffer(a5),d0
	move.l	FrontBuffer(a5),BackBuffer(a5)
	move.l	d0,FrontBuffer(a5)
	; falls through

;--
; ShowFront
; Point the copper list's bitplane pointers at the front buffer.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0
ShowFront:
	move.l	FrontBuffer(a5),d0
	add.l	#VISIBLE,d0
	lea	CopperPlanes+2,a0
	moveq	#PLANES-1,d1
.Plane	swap	d0
	move.w	d0,(a0)
	swap	d0
	move.w	d0,4(a0)
	addq.l	#8,a0
	add.l	#PLANE_BYTES,d0
	dbf	d1,.Plane
	rts

;--
; VBlank
; Level 3 interrupt: count the frame.
; In:       -
; Out:      -
; Clobbers: -
VBlank:	move.l	a5,-(sp)
	lea	State,a5
	addq.w	#1,FrameCount(a5)
	move.w	#INT_VERTB,CUSTOM+intreq
	move.l	(sp)+,a5
	rte

	section	chip_data,data_c

Copper:	dc.w	diwstrt,DIW_START,diwstop,DIW_STOP
	dc.w	ddfstrt,DDF_START,ddfstop,DDF_STOP
	dc.w	bplcon0,BPLCON0_4PLANES,bplcon1,0,bplcon2,PRIORITY
	dc.w	bpl1mod,ROW_BYTES-DISPLAY_BYTES,bpl2mod,ROW_BYTES-DISPLAY_BYTES
CopperPlanes:
	dc.w	bplpt+0,0,bplpt+2,0,bplpt+4,0,bplpt+6,0
	dc.w	bplpt+8,0,bplpt+10,0,bplpt+12,0,bplpt+14,0
CopperSprites:
	dc.w	sprpt+0,0,sprpt+2,0,sprpt+4,0,sprpt+6,0
	dc.w	sprpt+8,0,sprpt+10,0,sprpt+12,0,sprpt+14,0
	dc.w	sprpt+16,0,sprpt+18,0,sprpt+20,0,sprpt+22,0
	dc.w	sprpt+24,0,sprpt+26,0,sprpt+28,0,sprpt+30,0
	; the playfield's 16 colours: black, then the arcade's 15 for enemies and text
	dc.w	color+0,$000,color+2,$ddf,color+4,$f00,color+6,$ff0
	dc.w	color+8,$06f,color+10,$0ff,color+12,$f0f,color+14,$0f0
	dc.w	color+16,$d40,color+18,$09a,color+20,$90f,color+22,$00f
	dc.w	color+24,$fb0,color+26,$f90,color+28,$0bf,color+30,$b0f
	dc.l	COPPER_END

NullSprite:
	dc.w	0,0

	section	chip_bss,bss_c

Screens:
Screen1:	ds.b	SCREEN_SIZE
Screen2:	ds.b	SCREEN_SIZE
