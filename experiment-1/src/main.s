;----------------------------------------------------------------------
; experiment-1: can a stock A500 move NBOBS Galaga enemies at 50 fps?
;
; 16x16 masked blitter bobs on a black 320x256 4-bitplane interleaved
; screen, double buffered, old positions erased with a clear blit.
; Fighter and two bullets are hardware sprites, so sprite DMA is on.
; Background turns blue from the raster line where the frame's work
; ended: blue = idle time. Left mouse button exits.
;
; Build options: -DNBOBS=n (multiple of 10), -DNONASTY (no blitter priority),
; -DFULLCLEAR (one play-area clear blit instead of one per bob),
; -DMEASURE=frames (run, then write timing + screen dump to "results").
;----------------------------------------------------------------------

	include	"gfx.i"

	ifnd	NBOBS
NBOBS	equ	50
	endc

BPR	equ	40			; bytes per bitplane row
ROWB	equ	BPR*4			; bytes per interleaved screen row
SCRSIZE	equ	ROWB*256
XMIN	equ	48			; 224 px Galaga playfield centred on 320
XRANGE	equ	224-16
YRANGE	equ	212
SHIPY	equ	236
BLTSZ	equ	(16*4)<<6+2		; 16 rows x 4 planes, 2 words wide
BOBSZ	equ	16			; x, y, dx, dy, 2 frame pointers
CLRW	equ	(XRANGE+32)/16		; play area width in words, for FULLCLEAR

CUSTOM	equ	$dff000
dmaconr	equ	$002
vposr	equ	$004
intenar	equ	$01c
bltcon0	equ	$040
bltafwm	equ	$044
bltcpt	equ	$048
bltbpt	equ	$04c
bltapt	equ	$050
bltdpt	equ	$054
bltsize	equ	$058
bltcmod	equ	$060
bltamod	equ	$064
bltdmod	equ	$066
cop1lc	equ	$080
copjmp1	equ	$088
dmacon	equ	$096
intena	equ	$09a
intreq	equ	$09c
color00	equ	$180

OldOpenLibrary equ -408
CloseLibrary equ -414
Forbid	equ	-132
Permit	equ	-138
LoadView equ	-222
WaitTOF	equ	-270
gb_ActiView equ	34
gb_copinit equ	38

WAITBLIT macro
	tst.b	dmaconr(a6)
.wb\@	btst	#6,dmaconr(a6)
	bne.s	.wb\@
	endm

	section	code,code

start:	move.l	4.w,a6
	lea	gfxname(pc),a1
	jsr	OldOpenLibrary(a6)
	move.l	d0,a5
	move.l	gb_ActiView(a5),-(sp)
	exg	a5,a6			; a6 = gfx, a5 = exec
	sub.l	a1,a1
	jsr	LoadView(a6)
	jsr	WaitTOF(a6)
	jsr	WaitTOF(a6)
	exg	a5,a6
	jsr	Forbid(a6)
	move.l	a5,-(sp)

	lea	CUSTOM,a6
	WAITBLIT
	move.w	intenar(a6),-(sp)
	move.w	dmaconr(a6),-(sp)
	move.w	#$7fff,d0
	move.w	d0,intena(a6)
	move.w	d0,intreq(a6)
	move.w	d0,dmacon(a6)
	move.l	$6c.w,-(sp)
	lea	vbi(pc),a0
	move.l	a0,$6c.w

	lea	bssmem,a0			; KS 1.x does not clear BSS
	move.w	#BSSSIZE/4-1,d7
.clr	clr.l	(a0)+
	dbf	d7,.clr

	lea	screen1,a2		; a2 = front buffer, a3 = back buffer
	lea	screen2,a3
	move.l	a2,a0			; erase list sits just below its screen
	move.l	a3,a1
	moveq	#NBOBS-1,d7
.old	move.l	a2,-(a0)
	move.l	a3,-(a1)
	dbf	d7,.old

	lea	sprtab(pc),a0		; sprite pointers into the copper list
	lea	cop_spr+2,a1
	moveq	#8*2-1,d7
.spr	move.w	(a0)+,(a1)
	addq.l	#4,a1
	dbf	d7,.spr

	move.l	a2,d0
	bsr	show
	move.l	#copper,cop1lc(a6)
	move.w	d0,copjmp1(a6)
	ifd	NONASTY
	move.w	#$83e0,dmacon(a6)	; bitplane, copper, blitter, sprite
	else
	move.w	#$87e0,dmacon(a6)	; + blitter priority over the CPU
	endc
	move.w	#$0020,intreq(a6)	; drop the vblank that init slept through
	move.w	#$c020,intena(a6)	; vertical blank

;----------------------------------------------------------------------
mainloop:
	move.w	frame(pc),d0		; wait for the next vertical blank
.sync	cmp.w	frame(pc),d0
	beq.s	.sync
	ifd	MEASURE
	move.w	frame(pc),fstart
	endc

	; --- hardware sprites: fighter + two bullets
	lea	ship(pc),a5
	move.w	(a5)+,d0
	add.w	(a5),d0
	cmp.w	#XRANGE,d0
	bls.s	.shipx
	neg.w	(a5)
	add.w	(a5),d0
.shipx	move.w	d0,-2(a5)
	addq.l	#2,a5
	move.w	d0,d5			; d5 = ship x for bullet respawn
	move.w	#SHIPY,d1
	lea	sprship,a0
	bsr	setspr
	lea	sprbul1,a0
	bsr	bullet
	lea	sprbul2,a0
	bsr	bullet

	ifd	FULLCLEAR
	; --- clear the whole play area of this buffer in one blit
	lea	XMIN/8(a3),a0
	move.l	#$01000000,bltcon0(a6)	; D only, minterm 0
	move.w	#BPR-CLRW*2,bltdmod(a6)
	move.l	a0,bltdpt(a6)
	move.w	#(((YRANGE+16)*4)<<6)+CLRW,bltsize(a6)
	else
	; --- erase the bobs drawn into this buffer two frames ago
	lea	-NBOBS*4(a3),a4
	move.l	#$01000000,bltcon0(a6)	; D only, minterm 0
	move.w	#BPR-4,bltdmod(a6)
	moveq	#NBOBS-1,d7
.erase	move.l	(a4)+,a0
	WAITBLIT
	move.l	a0,bltdpt(a6)
	move.w	#BLTSZ,bltsize(a6)
	dbf	d7,.erase
	endc

	; --- move and draw
	move.w	frame(pc),d6		; wing flap: frame pointer 0 or 1
	lsr.w	#2,d6
	and.w	#4,d6
	ifnd	FULLCLEAR
	lea	-NBOBS*4(a3),a4
	endc
	lea	bobs(pc),a5
	moveq	#NBOBS-1,d7
	WAITBLIT
	move.l	#$ffff0000,bltafwm(a6)	; mask out the second mask word
	move.l	#(BPR-4)<<16+$fffe,bltcmod(a6)	; C modulo, B modulo -2
	move.l	#$fffe<<16+BPR-4,bltamod(a6)	; A modulo -2, D modulo
.draw	movem.w	(a5),d0-d3		; x, y, dx, dy
	add.w	d2,d0
	cmp.w	#XRANGE,d0
	bls.s	.xok
	neg.w	d2
	add.w	d2,d0
.xok	add.w	d3,d1
	cmp.w	#YRANGE,d1
	bls.s	.yok
	neg.w	d3
	add.w	d3,d1
.yok	movem.w	d0-d3,(a5)
	move.l	8(a5,d6.w),a0		; image, mask follows at +128
	lea	BOBSZ(a5),a5
	mulu	#ROWB,d1
	moveq	#15,d4
	and.w	d0,d4
	ror.w	#4,d4			; shift in bits 15-12
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	lea	XMIN/8(a3,d1.l),a1	; destination word
	move.w	d4,d5
	or.w	#$0fca,d5		; A=mask B=image C=D=screen, cookie cut
	swap	d5
	move.w	d4,d5			; bltcon0:bltcon1
	ifnd	FULLCLEAR
	move.l	a1,(a4)+		; remember for the erase pass
	endc
	WAITBLIT
	move.l	d5,bltcon0(a6)
	move.l	a0,bltbpt(a6)
	lea	128(a0),a0
	move.l	a0,bltapt(a6)
	move.l	a1,bltcpt(a6)
	move.l	a1,bltdpt(a6)
	move.w	#BLTSZ,bltsize(a6)
	dbf	d7,.draw

	WAITBLIT
	move.w	#$004,color00(a6)	; idle from here to the next frame
	ifd	MEASURE
	move.l	vposr(a6),d0
	lsr.l	#8,d0
	and.l	#$1ff,d0		; raster line where the work ended
	move.w	frame(pc),d1
	sub.w	fstart(pc),d1
	mulu	#313,d1			; plus whole frames overrun
	add.w	d1,d0
	lea	stats(pc),a0
	cmp.w	(a0),d0
	bls.s	.nomax
	move.w	d0,(a0)
.nomax	add.l	d0,2(a0)
	addq.w	#1,6(a0)
	endc

	move.l	a3,d0			; show what was just drawn
	bsr	show
	exg	a2,a3
	ifd	MEASURE
	cmp.w	#MEASURE,stats+6
	beq.s	exit
	endc
	btst	#6,$bfe001
	bne	mainloop

;----------------------------------------------------------------------
exit:	WAITBLIT
	move.w	#$7fff,d0
	move.w	d0,intena(a6)
	move.w	d0,intreq(a6)
	move.w	d0,dmacon(a6)
	move.l	(sp)+,$6c.w
	move.w	(sp)+,d1
	move.w	(sp)+,d2
	move.l	(sp)+,a5
	move.l	gb_copinit(a5),cop1lc(a6)
	or.w	#$8000,d1
	or.w	#$c000,d2
	move.w	d1,dmacon(a6)
	move.w	d2,intena(a6)
	move.l	a5,a6
	move.l	(sp)+,a1
	jsr	LoadView(a6)
	jsr	WaitTOF(a6)
	jsr	WaitTOF(a6)
	move.l	a6,a1
	move.l	4.w,a6
	jsr	CloseLibrary(a6)
	jsr	Permit(a6)
	ifd	MEASURE
	include	"measure.i"
	endc
	moveq	#0,d0
	rts

;----------------------------------------------------------------------
; d0 = screen to display
show:	lea	cop_bpl+2,a0
	moveq	#4-1,d1
.plane	swap	d0
	move.w	d0,(a0)
	swap	d0
	move.w	d0,4(a0)
	addq.l	#8,a0
	moveq	#BPR,d2
	add.l	d2,d0
	dbf	d1,.plane
	rts

; a5 = bullet x,y  a0 = sprite  d5 = ship x
bullet:	subq.w	#6,2(a5)
	bpl.s	.fly
	move.w	d5,(a5)
	move.w	#SHIPY-16,2(a5)
.fly	move.w	(a5)+,d0
	move.w	(a5)+,d1

; d0 = x, d1 = y, a0 = 16-line sprite: write its two control words
setspr:	add.w	#XMIN+$80,d0
	add.w	#$2c,d1
	moveq	#16,d2
	add.w	d1,d2			; vstop
	moveq	#0,d3
	lsl.w	#8,d1
	addx.b	d3,d3			; vstart bit 8
	lsl.w	#8,d2
	addx.b	d3,d3			; vstop bit 8
	lsr.w	#1,d0
	addx.b	d3,d3			; hstart bit 0
	move.b	d0,d1
	move.b	d3,d2
	move.w	d1,(a0)+
	move.w	d2,(a0)
	rts

vbi:	addq.w	#1,frame
	move.w	#$0020,CUSTOM+intreq
	rte

;----------------------------------------------------------------------
frame:	dc.w	0
ship:	dc.w	XRANGE/2,2		; x, dx
	dc.w	0,100,0,220		; bullets: x, y
	ifd	MEASURE
fstart:	dc.w	0
stats:	dc.w	0			; worst frame, raster lines
	dc.l	0			; total raster lines
	dc.w	0			; frames drawn
	endc
sprtab:	dc.l	sprship,sprbul1,sprbul2
	dc.l	sprnull,sprnull,sprnull,sprnull,sprnull
gfxname: dc.b	"graphics.library",0
	even

seed	set	$2c7b
RND	macro
seed	set	(seed*25173+13849)&$ffff
	endm

BOB	macro				; \1 \2 = wings open / closed frames
	RND
	dc.w	(seed>>4)//(XRANGE+1)
	RND
	dc.w	(seed>>4)//(YRANGE+1)
	RND
	dc.w	(1+(seed>>5)//3)*(1-((seed>>12)&2))	; dx +-1..3
	RND
	dc.w	(1+(seed>>5)//2)*(1-((seed>>12)&2))	; dy +-1..2
	dc.l	enemies+\1,enemies+\2
	endm

bobs:	rept	NBOBS/10
	BOB	GFX_BOSS+6*FRAME_SIZE,GFX_BOSS+7*FRAME_SIZE
	BOB	GFX_BUTTERFLY+6*FRAME_SIZE,GFX_BUTTERFLY+7*FRAME_SIZE
	BOB	GFX_BEE+6*FRAME_SIZE,GFX_BEE+7*FRAME_SIZE
	BOB	GFX_BOSSHIT+6*FRAME_SIZE,GFX_BOSSHIT+7*FRAME_SIZE
	BOB	GFX_SCORPION+6*FRAME_SIZE,GFX_SCORPION+6*FRAME_SIZE
	BOB	GFX_BOSCONIAN+6*FRAME_SIZE,GFX_BOSCONIAN+6*FRAME_SIZE
	BOB	GFX_GALAXIAN+6*FRAME_SIZE,GFX_GALAXIAN+6*FRAME_SIZE
	BOB	GFX_DRAGONFLY+6*FRAME_SIZE,GFX_DRAGONFLY+6*FRAME_SIZE
	BOB	GFX_SATELLITE+6*FRAME_SIZE,GFX_SATELLITE+6*FRAME_SIZE
	BOB	GFX_ENTERPRISE+6*FRAME_SIZE,GFX_ENTERPRISE+6*FRAME_SIZE
	endr

;----------------------------------------------------------------------
	section	gfx,data_c

copper:	dc.w	$008e,$2c81,$0090,$2cc1	; display window 320x256
	dc.w	$0092,$0038,$0094,$00d0	; data fetch
	dc.w	$0100,$4200,$0102,$0000	; 4 bitplanes
	dc.w	$0104,$0024		; sprites in front
	dc.w	$0108,ROWB-BPR,$010a,ROWB-BPR
cop_bpl: dc.w	$00e0,0,$00e2,0,$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0,$00ec,0,$00ee,0
cop_spr: dc.w	$0120,0,$0122,0,$0124,0,$0126,0
	dc.w	$0128,0,$012a,0,$012c,0,$012e,0
	dc.w	$0130,0,$0132,0,$0134,0,$0136,0
	dc.w	$0138,0,$013a,0,$013c,0,$013e,0
	COPPER_PALETTE
	dc.w	$ffff,$fffe

sprship: dc.w	0,0
	incbin	"sprites.bin",SPR_FIGHTER,64
	dc.w	0,0
sprbul1: dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET,64
	dc.w	0,0
sprbul2: dc.w	0,0
	incbin	"sprites.bin",SPR_BULLET,64
sprnull: dc.w	0,0

enemies: incbin	"enemies.bin"

;----------------------------------------------------------------------
	section	screens,bss_c

bssmem:	ds.l	NBOBS			; erase list of screen1
screen1: ds.b	SCRSIZE
	ds.l	NBOBS			; erase list of screen2
screen2: ds.b	SCRSIZE
BSSSIZE	equ	*-bssmem
