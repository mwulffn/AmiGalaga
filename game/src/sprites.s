; Sprites: the player's fighter and bullets, as hardware sprites.
;
; The game says where they are in the state (ShipX, Bullets); SpritesUpdate
; turns that into the sprites' control words. Call it straight after the
; vertical blank: the hardware reads the control words near the top of
; the frame.
;
; Sprite 0 is the fighter. Sprite 2 shows both bullets, one below the
; other: a sprite can be reused further down the screen as long as there
; is a line between the two images. The bullet's image is 8 lines tall
; and two bullets are normally 18 or more apart; if they are ever closer,
; the lower one is not shown that frame.

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

FIGHTER_SPRITE	equ	0
BULLET_SPRITE	equ	2
SPRITE_X0	equ	$80			; sprite position of the playfield's left edge
FIGHTER_LINES	equ	16
BULLET_TOP	equ	4			; the bullet's image starts this far down its 16x16 cell
BULLET_LINES	equ	8
LINE_WORDS	equ	2			; a sprite line is two words
CONTROL_WORDS	equ	2

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
; Clobbers: d0-d5, a0
SpritesUpdate:
	move.w	ShipX(a5),d0
	move.w	#SHIP_Y,d1
	moveq	#FIGHTER_LINES,d2
	lea	Fighter,a0
	bsr	Place

	; the upper bullet goes first in the sprite; a bullet with a negative y is not there
	movem.w	Bullets(a5),d0-d1/d4-d5		; x, y of each
	tst.w	d1
	bmi	.Swap
	tst.w	d5
	bmi	.Ordered
	cmp.w	d1,d5
	bge	.Ordered
.Swap	exg	d0,d4
	exg	d1,d5
.Ordered
	lea	BulletPair,a0
	tst.w	d1
	bmi	.None
	tst.w	d5
	bmi	.Upper
	move.w	d5,d3
	sub.w	d1,d3				; how far below the upper one the lower one is
	cmp.w	#BULLET_LINES+1,d3
	bge	.Upper
	moveq	#-1,d5				; too close for one sprite to show both
.Upper	addq.w	#BULLET_TOP,d1
	moveq	#BULLET_LINES,d2
	bsr	Place
	lea	BulletSecond-BulletPair(a0),a0
	tst.w	d5
	bmi	.None
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

BulletPair:
	dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET+BULLET_TOP*LINE_WORDS*2,BULLET_LINES*LINE_WORDS*2
BulletSecond:
	dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET+BULLET_TOP*LINE_WORDS*2,BULLET_LINES*LINE_WORDS*2
	dc.w	0,0
