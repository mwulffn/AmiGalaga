; Sprites: the player's fighter and bullets, as hardware sprites.
;
; The game says where they are in the state (ShipX, Shots); SpritesUpdate
; turns that into the sprites' control words. Call it straight after the
; vertical blank: the hardware reads the control words near the top of
; the frame.
;
; Sprite 0 is the fighter; when it blows up, sprites 0 and 1 show the two
; halves of the explosion. Sprite 4, with its own colours, is the captured
; (red) fighter. Both fighters can be turned any way: in the tractor beam
; the fighter spins, and the captured one flies with its boss.
; With two fighters, the second is on sprite 1 and its bullets on sprite 3;
; when one of the two blows up, its explosion is on sprites 4 and 5, whose
; colours are changed in the copper list for it, as they are for a rescued
; (white) fighter. Sprite 2 shows both bullets, one below the
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
	xref	FarList
	xref	CaptiveColours
	xref	FighterColour

FIGHTER_SPRITE	equ	0
BULLET_SPRITE	equ	2
FAR_SPRITE	equ	6			; the far stars (stars.s)
CAPTIVE_SPRITE	equ	4
DUAL_STEP	equ	15			; the second of two fighters is this far right of the first
COLOUR_STEP	equ	4			; from one colour's value to the next in the copper list
UPRIGHT_IMAGE	equ	6			; in Spin: not flipped, frame 6
SPRITE_X0	equ	$80			; sprite position of the playfield's left edge
FIGHTER_LINES	equ	16
BULLET_TOP	equ	4			; the bullet's image starts this far down its 16x16 cell
BULLET_LINES	equ	8
BULLET_BLOCK	equ	(CONTROL_WORDS+BULLET_LINES*LINE_WORDS)*2	; a bullet in a sprite: its control words and image
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
; Give the fighter, the bullets and the far stars their sprites.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1, a0-a1
SpritesInit:
	move.w	#UPRIGHT_IMAGE,FighterShown
	move.w	#UPRIGHT_IMAGE,CaptiveShown
	moveq	#FIGHTER_SPRITE,d0
	lea	Fighter,a0
	bsr	VideoSetSprite
	moveq	#BULLET_SPRITE,d0
	lea	BulletPair,a0
	bsr	VideoSetSprite
	moveq	#BULLET_SPRITE+1,d0
	lea	BulletPair2,a0
	bsr	VideoSetSprite
	moveq	#FAR_SPRITE,d0			; the far stars: their list is the stars' business
	lea	FarList,a0
	bra	VideoSetSprite

;--
; SpritesUpdate
; Move the sprites to where the state says the fighter and bullets are.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a2
SpritesUpdate:
	; sprites 0 and 1: the fighter (and a second beside it), its explosion, or nothing
	move.w	#FIGHTER_BLUE,d5
	lea	NoSprite,a2			; what sprite 1 shows
	lea	Fighter,a0
	move.b	PlayerState(a5),d0
	beq	.Whole
	cmp.b	#PS_READY,d0
	beq	.Whole
	cmp.b	#PS_TAKEN,d0
	bne	.Lost
	tst.b	ShipGone(a5)			; in the beam: until it turns red and is the captive
	beq	.Whole
.Lost	move.l	a2,a0
	moveq	#0,d0
	move.b	FighterStep(a5),d0
	beq	.Show				; gone
	lea	Bang,a0
	move.w	ShipX(a5),d4
	bsr	BangPlace
	move.w	#BANG_CYAN,d5
	bra	.Show
.Whole	moveq	#0,d0				; its image: by flip and frame
	move.b	ShipCtrl(a5),d0
	lsl.w	#3,d0
	add.b	ShipCode(a5),d0
	lea	FighterShown,a1
	bsr	Turned
	move.w	ShipX(a5),d0
	move.w	ShipSY(a5),d1
	sub.w	#DISPLAY_SY,d1
	moveq	#FIGHTER_LINES,d2
	bsr	Place
	tst.b	Dual(a5)
	beq	.Show
	lea	Fighter2,a2
	exg	a0,a2
	move.w	ShipX(a5),d0
	add.w	#DUAL_STEP,d0
	move.w	#SHIP_Y,d1
	moveq	#FIGHTER_LINES,d2
	bsr	Place
	exg	a0,a2
.Show	move.w	d5,FighterColour
	moveq	#FIGHTER_SPRITE,d0
	bsr	VideoSetSprite
	move.l	a2,a0
	moveq	#FIGHTER_SPRITE+1,d0
	bsr	VideoSetSprite

	; sprites 4 and 5: one of two fighters blowing up, or the captured fighter (red, or
	; white once it is rescued) on sprite 4. There is no captured fighter while there are
	; two, so the two uses never meet.
	lea	NoSprite,a2
	moveq	#0,d0
	move.b	Bang2Step(a5),d0
	beq	.Captive
	lea	Bang2,a0
	move.w	Bang2X(a5),d4
	bsr	BangPlace
	lea	BangColours(pc),a1
	bra	.Pair
.Captive
	lea	NoSprite,a0
	tst.b	CaptiveState(a5)
	beq	.Free
	move.w	CaptiveY(a5),d1
	sub.w	#DISPLAY_SY,d1
	cmp.w	#-FIGHTER_LINES,d1		; off the top: not shown
	ble	.Free
	cmp.w	#DISPLAY_LINES,d1
	bge	.Free
	move.w	CaptiveX(a5),d0
	sub.w	#DISPLAY_SX,d0
	cmp.w	#PLAY_WIDTH,d0			; in the gap or beyond: not shown either
	bcc	.Free
	movem.w	d0-d1,-(sp)
	moveq	#0,d0
	move.b	CaptiveCtrl(a5),d0
	lsl.w	#3,d0
	add.b	CaptiveCode(a5),d0
	lea	Captive,a0
	lea	CaptiveShown,a1
	bsr	Turned
	movem.w	(sp)+,d0-d1
	moveq	#FIGHTER_LINES,d2
	bsr	Place
.Free	lea	RedColours(pc),a1
	tst.b	CaptiveWhite(a5)
	beq	.Pair
	lea	WhiteColours(pc),a1
.Pair	move.w	(a1)+,CaptiveColours
	move.w	(a1)+,CaptiveColours+COLOUR_STEP
	move.w	(a1),CaptiveColours+2*COLOUR_STEP
	moveq	#CAPTIVE_SPRITE,d0
	bsr	VideoSetSprite
	move.l	a2,a0
	moveq	#CAPTIVE_SPRITE+1,d0
	bsr	VideoSetSprite

	; the bullets: every shot on sprite 2, and two fighters' second bullets on sprite 3
	lea	BulletPair,a0
	moveq	#0,d5
	bsr	Bullets
	lea	BulletPair2,a0
	moveq	#DUAL_STEP,d5
	bra	Bullets

; what the colour registers of sprites 4 and 5 hold for each of their uses
RedColours:
	dc.w	$bbf,$06f,$f00
WhiteColours:
	dc.w	$f00,$06f,$ddf
BangColours:
	dc.w	$f00,$0ff,$ddf

;--
; BangPlace
; Place the two halves of a fighter's explosion.
; In:       d0.w = steps of it left, 1 or more, d4.w = the fighter's playfield x,
;           a0 = the explosion's frames, of the pair of sprites that will show it
; Out:      a0 = the sprite for its left half, a2 = for its right
; Clobbers: d0-d3
BangPlace:
	; frame = 3 - (step - 1) / 4; a frame's left and right halves follow each other
	subq.w	#1,d0
	lsr.w	#2,d0
	eor.w	#BANG_FRAMES-1,d0
	mulu.w	#2*BANG_BLOCK,d0
	add.w	d0,a0
	move.w	d4,d0
	subq.w	#BANG_OFFSET,d0
	move.w	#SHIP_Y-BANG_OFFSET,d1
	moveq	#BANG_LINES,d2
	bsr	Place
	lea	BANG_BLOCK(a0),a2
	exg	a0,a2
	move.w	d4,d0
	addq.w	#16-BANG_OFFSET,d0
	move.w	#SHIP_Y-BANG_OFFSET,d1
	moveq	#BANG_LINES,d2
	bsr	Place
	exg	a0,a2
	rts

;--
; Bullets
; Put the shots' bullets on one sprite, the top one first. A sprite can show them only one
; under the other with a line between, which the firing sees to (player.s); one that is
; too close to the one above it all the same is left out.
; In:       a0 = the sprite, d5.w = 0 for every shot's own bullet, or how far right of it
;           the second bullet of a shot from two fighters is, a5 = state
; Out:      -
; Clobbers: d0-d4, a0-a2
Bullets:
	; the bullets that show, sorted by line into ShotList
	lea	Shots(a5),a1
	lea	ShotList(a5),a2
	moveq	#0,d4				; how many
	moveq	#MAX_SHOTS-1,d3
.Shot	bsr	ShotPlace
	cmp.w	#NOT_SHOWN,d1
	beq	.Next
	move.w	d4,d2
	lsl.w	#2,d2				; where it goes if none above it is lower
.Above	beq	.Put
	cmp.w	-2(a2,d2.w),d1
	bge	.Put
	move.l	-4(a2,d2.w),(a2,d2.w)
	subq.w	#4,d2
	bra	.Above
.Put	move.w	d0,(a2,d2.w)
	move.w	d1,2(a2,d2.w)
	addq.w	#1,d4
.Next	lea	sh_SIZEOF(a1),a1
	dbf	d3,.Shot
	move.w	#NOT_SHOWN,a1			; the line of the one above
.Show	subq.w	#1,d4
	bmi	.End
	move.w	(a2)+,d0
	move.w	(a2)+,d1
	move.w	d1,d2
	sub.w	a1,d2
	cmp.w	#BULLET_LINES+1,d2
	blt	.Show
	move.w	d1,a1
	addq.w	#BULLET_TOP,d1
	moveq	#BULLET_LINES,d2
	bsr	Place
	lea	BULLET_BLOCK(a0),a0
	bra	.Show
.End	clr.l	(a0)				; empty control words end the sprite
	rts

;--
; ShotPlace
; Where a shot's bullet shows.
; In:       a1 = the shot, d5.w = 0 for its own bullet, or how far right its second one is
; Out:      d0.w = playfield x, d1.w = display line, or NOT_SHOWN if it does not show: not in
;           flight, above the display, or no second bullet
; Clobbers: -
ShotPlace:
	move.w	sh_x(a1),d0
	beq	.No
	tst.w	d5
	beq	.Any
	tst.b	sh_wide(a1)
	beq	.No
.Any	add.w	d5,d0
	sub.w	#DISPLAY_SX,d0
	move.w	sh_y(a1),d1
	sub.w	#DISPLAY_SY,d1
	cmp.w	#-BULLET_TOP-BULLET_LINES,d1
	bgt	.Is
.No	move.w	#NOT_SHOWN,d1
.Is	rts

;--
; Turned
; Give a fighter's sprite the image for the way it is turned, if it has another.
; In:       a0 = the sprite: control words, then 16 lines, d0.w = the image: flip * 8 + frame,
;           a1 = where the sprite's present image number is kept
; Out:      -
; Clobbers: d0-d1, a1
Turned:	cmp.w	(a1),d0
	beq	.Same
	move.w	d0,(a1)
	lsl.w	#6,d0				; 16 lines of two words an image
	lea	Spin,a1
	add.w	d0,a1
	moveq	#0,d1
.Line	move.l	(a1)+,CONTROL_WORDS*2(a0,d1.w)
	addq.w	#LINE_WORDS*2,d1
	cmp.w	#FIGHTER_LINES*LINE_WORDS*2,d1
	bne	.Line
.Same	rts

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

; the fighter and the captured fighter: their images are copied in from Spin as they turn
Fighter:
	dc.w	0,0
	incbin	"sprites.bin",SPR_FIGHTER,FIGHTER_LINES*LINE_WORDS*2
	dc.w	0,0
Captive:
	dc.w	0,0
	incbin	"sprites.bin",SPR_FIGHTER,FIGHTER_LINES*LINE_WORDS*2
	dc.w	0,0
; the second of two fighters: always upright
Fighter2:
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

; the same again for sprites 4 and 5: a sprite's position is in its data, and both
; explosions can show at once
Bang2:
HALF	set	0
	rept	2*BANG_FRAMES
	dc.w	0,0
	incbin	"sprites.bin",SPR_BANG+HALF*BANG_LINES*LINE_WORDS*2,BANG_LINES*LINE_WORDS*2
	dc.w	0,0
HALF	set	HALF+1
	endr

; a sprite of bullets: MAX_SHOTS of them, each with its control words, and the end
BULLETS	macro
	rept	MAX_SHOTS
	dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET+BULLET_TOP*LINE_WORDS*2,BULLET_LINES*LINE_WORDS*2
	endr
	dc.w	0,0
	endm
BulletPair:
	BULLETS
; two fighters' second bullets
BulletPair2:
	BULLETS

	section	data,data

; the fighter in every direction: 4 flips x 8 frames, 16 lines of two words each
Spin:	incbin	"sprites.bin",SPR_SPIN,4*8*FIGHTER_LINES*LINE_WORDS*2

	section	bss,bss

; which of Spin's images each of the two sprites holds
FighterShown:	ds.w	1
CaptiveShown:	ds.w	1
