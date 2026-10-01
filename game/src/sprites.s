; Sprites: the player's fighter and bullets, as hardware sprites.
;
; The game says where they are in the state (ShipX, Shots); SpritesUpdate
; turns that into the sprites' control words. Call it straight after the
; vertical blank: the hardware reads the control words near the top of
; the frame.
;
; Sprite 0 is the fighter; when it blows up, sprites 0 and 1 show the two
; halves of the explosion. Sprite 2 shows both bullets, one below the
; other: a sprite can be reused further down the screen as long as there
; is a line between the two images. The bullet's image is 8 lines tall,
; and the game does not fire a second shot until the first is 9 lines up
; (player.s), so both always fit.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"gfx.i"

	xdef	SpritesInit
	xdef	SpritesUpdate
	xref	VideoSetSprite
	xref	FighterColour

FIGHTER_SPRITE	equ	0
BULLET_SPRITE	equ	2
SPRITE_X0	equ	$80			; sprite position of the playfield's left edge
FIGHTER_LINES	equ	16
BULLET_TOP	equ	4			; the bullet's image starts this far down its 16x16 cell
BULLET_LINES	equ	8
LINE_WORDS	equ	2			; a sprite line is two words
CONTROL_WORDS	equ	2
NOT_SHOWN	equ	-$4000			; a display line no shot can have
; The fighter's explosion: 32x32, its left half on sprite 0 and its right on sprite 1. The pair's
; colour registers hold the fighter's red, blue and white; the explosion is red, cyan and white,
; so the blue one is changed in the copper list while it shows.
BANG_FRAMES	equ	4
BANG_LINES	equ	32
BANG_OFFSET	equ	8			; it starts this far up and left of the fighter
BANG_BLOCK	equ	(CONTROL_WORDS+BANG_LINES*LINE_WORDS+CONTROL_WORDS)*2
FIGHTER_BLUE	equ	$06f
BANG_CYAN	equ	$0ff

	section	code,code

;--
; SpritesInit
; Give the fighter and the bullets their sprites.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0-a1
SpritesInit:
	moveq	#FIGHTER_SPRITE,d0
	lea	Fighter,a0
	bsr	VideoSetSprite
	moveq	#BULLET_SPRITE,d0
	lea	BulletPair,a0
	bra	VideoSetSprite

;--
; SpritesUpdate
; Move the sprites to where the state says the fighter and bullets are.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a2
SpritesUpdate:
	; the fighter: itself, its explosion on sprites 0 and 1, or nothing
	move.w	#FIGHTER_BLUE,d5
	lea	NoSprite,a2			; what sprite 1 shows
	lea	Fighter,a0
	move.b	PlayerState(a5),d0
	beq	.Whole
	cmp.b	#PS_READY,d0
	beq	.Whole
	move.l	a2,a0
	moveq	#0,d0
	move.b	FighterStep(a5),d0
	beq	.Show				; gone
	; frame = 3 - (step - 1) / 4; a frame's left and right halves follow each other
	subq.w	#1,d0
	lsr.w	#2,d0
	eor.w	#BANG_FRAMES-1,d0
	mulu.w	#2*BANG_BLOCK,d0
	lea	Bang,a0
	add.w	d0,a0
	lea	BANG_BLOCK(a0),a2
	move.w	#BANG_CYAN,d5
	move.w	ShipX(a5),d0
	subq.w	#BANG_OFFSET,d0
	move.w	#SHIP_Y-BANG_OFFSET,d1
	moveq	#BANG_LINES,d2
	bsr	Place
	exg	a0,a2
	move.w	ShipX(a5),d0
	addq.w	#16-BANG_OFFSET,d0
	move.w	#SHIP_Y-BANG_OFFSET,d1
	moveq	#BANG_LINES,d2
	bsr	Place
	exg	a0,a2
	bra	.Show
.Whole	move.w	ShipX(a5),d0
	move.w	#SHIP_Y,d1
	moveq	#FIGHTER_LINES,d2
	bsr	Place
.Show	move.w	d5,FighterColour
	moveq	#FIGHTER_SPRITE,d0
	bsr	VideoSetSprite
	move.l	a2,a0
	moveq	#FIGHTER_SPRITE+1,d0
	bsr	VideoSetSprite

	; a shot's playfield x and display line; one that is not in flight, or is above the
	; display, is not shown
	movem.w	Shots(a5),d0-d1/d4-d5		; x, y of each, as the arcade counts
	tst.w	d0
	beq	.No0
	sub.w	#DISPLAY_SX,d0
	sub.w	#DISPLAY_SY,d1
	cmp.w	#-BULLET_TOP-BULLET_LINES,d1
	bgt	.Is0
.No0	move.w	#NOT_SHOWN,d1
.Is0	tst.w	d4
	beq	.No1
	sub.w	#DISPLAY_SX,d4
	sub.w	#DISPLAY_SY,d5
	cmp.w	#-BULLET_TOP-BULLET_LINES,d5
	bgt	.Is1
.No1	move.w	#NOT_SHOWN,d5
.Is1	; the upper bullet goes first in the sprite
	cmp.w	#NOT_SHOWN,d1
	beq	.Swap
	cmp.w	#NOT_SHOWN,d5
	beq	.Ordered
	cmp.w	d1,d5
	bge	.Ordered
.Swap	exg	d0,d4
	exg	d1,d5
.Ordered
	lea	BulletPair,a0
	cmp.w	#NOT_SHOWN,d1
	beq	.None
	cmp.w	#NOT_SHOWN,d5
	beq	.Upper
	move.w	d5,d3
	sub.w	d1,d3				; how far below the upper one the lower one is
	cmp.w	#BULLET_LINES+1,d3
	bge	.Upper
	move.w	#NOT_SHOWN,d5			; too close for one sprite to show both
.Upper	addq.w	#BULLET_TOP,d1
	moveq	#BULLET_LINES,d2
	bsr	Place
	lea	BulletSecond-BulletPair(a0),a0
	cmp.w	#NOT_SHOWN,d5
	beq	.None
	move.w	d4,d0
	move.w	d5,d1
	addq.w	#BULLET_TOP,d1
	moveq	#BULLET_LINES,d2
	bra	Place
.None	clr.l	(a0)				; empty control words end the sprite
	rts

;--
; Place
; Write a sprite image's two control words.
; In:       a0 = the control words, d0.w = x in playfield pixels, d1.w = y in display lines,
;           d2.w = the image's height in lines
; Out:      -
; Clobbers: d0-d3
Place:	add.w	#SPRITE_X0,d0
	add.w	#DISPLAY_TOP,d1
	add.w	d1,d2				; the line after the last
	; control words: start line (low 8 bits), x / 2; stop line (low 8 bits),
	; then bit 2 = start line bit 8, bit 1 = stop line bit 8, bit 0 = x bit 0
	moveq	#0,d3
	lsl.w	#8,d1
	addx.b	d3,d3
	lsl.w	#8,d2
	addx.b	d3,d3
	lsr.w	#1,d0
	addx.b	d3,d3
	move.b	d0,d1
	move.b	d3,d2
	move.w	d1,(a0)
	move.w	d2,2(a0)
	rts

	section	chip_data,data_c

Fighter:
	dc.w	0,0
	incbin	"sprites.bin",SPR_FIGHTER,FIGHTER_LINES*LINE_WORDS*2
	dc.w	0,0

NoSprite:
	dc.w	0,0

; BANG_FRAMES frames, each its left half then its right, each with its own control words
Bang:
HALF	set	0
	rept	2*BANG_FRAMES
	dc.w	0,0
	incbin	"sprites.bin",SPR_BANG+HALF*BANG_LINES*LINE_WORDS*2,BANG_LINES*LINE_WORDS*2
	dc.w	0,0
HALF	set	HALF+1
	endr

BulletPair:
	dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET+BULLET_TOP*LINE_WORDS*2,BULLET_LINES*LINE_WORDS*2
BulletSecond:
	dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET+BULLET_TOP*LINE_WORDS*2,BULLET_LINES*LINE_WORDS*2
	dc.w	0,0
