;----------------------------------------------------------------------
; experiment-7: wait for the blitter, or feed it from an interrupt?
;
; The scene and the sound are experiment-6. What changes is how the
; frame's blits are issued, chosen at build time:
;
;   default   as before: each blit waits in a loop for the blitter to
;             be free, and the game logic runs after the drawing
;   -DQUEUE   the main code only writes each blit's registers into a
;             queue. A blitter-finished interrupt starts the next one.
;             The game logic runs straight after queueing, while the
;             blits are still going, and the frame ends when both are
;             done.
;
; The game logic is a stand-in: a loop that burns LOGIC * 10 CPU cycles
; without touching chip memory (default 25,000 cycles).
; Blue background = idle time. Left mouse button exits.
;
; Build options: -DQUEUE, -DLOGIC=n, -DNFLY=n (multiple of 10, may be
; 0), -DNOCOMPOSE, -DNONASTY (no blitter priority), -DMEASURE=frames.
;----------------------------------------------------------------------

	include	"gfx.i"

	ifnd	NFLY
NFLY	equ	10
	endc

BPR	equ	42			; bytes per bitplane row (336 px)
ROWB	equ	BPR*4			; bytes per interleaved screen row
GUARD	equ	16			; hidden rows above and below, hidden px left
SCRSIZE	equ	ROWB*(256+2*GUARD)
VISIBLE	equ	GUARD*ROWB+GUARD/8	; first displayed byte of a buffer
PLAYW	equ	224
XRANGE	equ	GUARD+PLAYW-1		; flyers: fully hidden left .. fully in the gap
YRANGE	equ	GUARD+256		; fully hidden above .. fully hidden below
SHIPX	equ	PLAYW-16		; fighter x range (playfield pixels)
SHIPY	equ	240
PANEL	equ	VISIBLE+(PLAYW+16)/8	; panel's top left byte in a buffer
BLTSZ	equ	(16*4)<<6+2		; 16 rows x 4 planes, 2 words wide
BOBSZ	equ	16			; x, y, dx, dy, 2 frame pointers

	ifnd	LOGIC
LOGIC	equ	2500			; stand-in game logic, in units of 10 CPU cycles
	endc

; A queued blit is the blitter's registers in address order, so the
; interrupt can copy it with nine moves: bltcon0, bltcon1, first and last
; word mask, the C, B, A and D pointers, the C, B, A and D modulos, and
; bltsize last because writing it starts the blit. Fields a blit does
; not use are left as they are.
Q_SIZE	equ	34
Q_MAX	equ	96			; blits per frame

; make the blit just written at -Q_SIZE(a2) visible, and start the queue if it has stopped
QKICK	macro
	move.l	a2,qtail
	tst.b	qidle
	beq.s	.k\@
	sf	qidle
	move.w	#$8040,intreq(a6)	; as if a blit had just finished
.k\@
	endm

CX	equ	GUARD+PLAYW/2-8		; formation centre minus half the sway
FY	equ	GUARD+20		; top row
SWAY	equ	16			; sway range in pixels
SPREAD	equ	4			; column pitch breathes 16..16+SPREAD
NROWS	equ	5

STARSZ	equ	12			; copper table entry: 2 moves + wait
STARCPY	equ	256*STARSZ		; the table is stored twice, this far apart
TO128	equ	128-44			; entries from the first line to raster line 128
TO256	equ	256-44

; formation row: strip, image, then words
r_gfx	equ	4
r_w	equ	8			; strip width in words
r_ncols	equ	10
r_first	equ	12			; first column used (of 10)
r_idx	equ	14			; row number
r_x	equ	16			; screen x of the strip (before sway)
r_y	equ	18
ROWSZ	equ	20

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
cop2lc	equ	$084
copjmp1	equ	$088
dmacon	equ	$096
intena	equ	$09a
intreq	equ	$09c
intreqr	equ	$01e
color00	equ	$180

OldOpenLibrary equ -408
CloseLibrary equ -414
Forbid	equ	-132
SuperState equ	-150
UserState equ	-156
Permit	equ	-138
LoadView equ	-222
WaitTOF	equ	-270
gb_ActiView equ	34
gb_copinit equ	38
gb_LOFlist equ	50

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
	; Run in supervisor mode on our own stack. Interrupts then push their
	; frames there, not on the system's supervisor stack in chip RAM, where
	; every access waits for the blitter when it has priority.
	jsr	SuperState(a6)
	move.l	d0,-(sp)

	lea	CUSTOM,a6
	WAITBLIT
	move.w	intenar(a6),-(sp)
	move.w	dmaconr(a6),-(sp)
	move.w	#$7fff,d0
	move.w	d0,intena(a6)
	move.w	d0,intreq(a6)
	move.w	d0,dmacon(a6)
	move.l	$6c.w,-(sp)
	ifd	QUEUE
	lea	lev3(pc),a0
	else
	lea	vbi(pc),a0
	endc
	move.l	a0,$6c.w
	move.l	$78.w,-(sp)
	lea	snd_int(pc),a0
	move.l	a0,$78.w

	lea	bssmem,a0		; KS 1.x does not clear BSS
	move.w	#BSSSIZE/4-1,d7
.clr	clr.l	(a0)+
	dbf	d7,.clr

	lea	screen1,a2		; a2 = front buffer, a3 = back buffer
	lea	screen2,a3
	if	NFLY
	move.l	a2,a0			; erase list sits just below its screen
	move.l	a3,a1
	moveq	#NFLY-1,d7
.old	move.l	a2,-(a0)
	move.l	a3,-(a1)
	dbf	d7,.old
	endc

	lea	sprtab(pc),a0		; sprite pointers into the copper list
	lea	cop_spr+2,a1
	moveq	#8*2-1,d7
.spr	move.w	(a0)+,(a1)
	addq.l	#4,a1
	dbf	d7,.spr

	move.l	a2,a1			; static panel contents, both buffers
	bsr	panel
	move.l	a3,a1
	bsr	panel

	move.l	a2,d0
	bsr	show
	move.l	#stars,cop2lc(a6)
	move.l	#copper,cop1lc(a6)
	move.w	d0,copjmp1(a6)
	ifd	NONASTY
	move.w	#$83e0,dmacon(a6)	; bitplane, copper, blitter, sprite
	else
	move.w	#$87e0,dmacon(a6)	; + blitter priority over the CPU
	endc

	ifnd	QUEUE
	lea	rows(pc),a5		; build every strip once
	moveq	#NROWS-1,d5
.build	bsr	compose
	lea	ROWSZ(a5),a5
	dbf	d5,.build
	endc

	bsr	snd_init
	move.w	#$2020,intreq(a6)	; drop the interrupts that init slept through
	ifd	QUEUE
	move.w	#$2060,intreq(a6)
	move.w	#$e060,intena(a6)	; vertical blank, blitter, CIA-B timer
	move.l	a2,-(sp)
	lea	qbuf,a2
	move.l	a2,qhead
	move.l	a2,qtail
	lea	rows(pc),a5		; build every strip once, through the queue
	moveq	#NROWS-1,d5
.build	bsr	compose
	lea	ROWSZ(a5),a5
	dbf	d5,.build
	move.l	(sp)+,a2
.built	tst.b	qidle
	beq.s	.built
	else
	move.w	#$e020,intena(a6)	; vertical blank, CIA-B timer
	endc

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
	cmp.w	#SHIPX,d0
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

	ifnd	SNDTEST
	; --- sound: the start theme, then a busy stretch of game
	lea	snd_state,a0
	move.w	frame(pc),d0
	cmp.w	#50,d0
	bne.s	.notune
	move.b	#1,2*$0b(a0)
.notune	cmp.w	#420,d0
	bcs.s	.nosnd
	move.b	#1,(a0)			; formation pulse, following the breathing
	move.b	form+7(pc),s_dir(a0)
	lea	beats(pc),a1		; period, countdown, offset in snd_state
.beat	move.b	(a1)+,d1
	beq.s	.nosnd
	subq.b	#1,(a1)+
	bne.s	.rest
	move.b	d1,-1(a1)
	moveq	#0,d2
	move.b	(a1),d2
	move.b	#1,(a0,d2.w)
.rest	addq.l	#1,a1
	bra.s	.beat
.nosnd
	endc

	; --- score: 30 points every 8th frame, redrawn once per buffer
	moveq	#7,d0
	and.w	frame(pc),d0
	bne.s	.noscore
	lea	score+3(pc),a0
	lea	points+3(pc),a1
	sub.w	d0,d0			; clear X
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
	abcd	-(a1),-(a0)
	move.w	#2,stale
.noscore
	lea	stale(pc),a0
	tst.w	(a0)
	beq.s	.fresh
	subq.w	#1,(a0)
	lea	score(pc),a0		; 3 BCD bytes -> 6 digits
	lea	digits(pc),a1
	moveq	#3-1,d1
.digit	move.b	(a0)+,d2
	move.b	d2,d3
	lsr.b	#4,d2
	and.b	#15,d3
	add.b	#'0',d2
	add.b	#'0',d3
	move.b	d2,(a1)+
	move.b	d3,(a1)+
	dbf	d1,.digit
	lea	digits(pc),a0
	lea	PANEL+50*ROWB+2(a3),a1
	moveq	#1,d0			; white
	bsr	print
.fresh

	; --- formation: sway every frame, breathe every 8th
	lea	form(pc),a5
	move.w	(a5)+,d0
	add.w	(a5),d0
	cmp.w	#SWAY,d0
	bls.s	.sway
	neg.w	(a5)
	add.w	(a5),d0
.sway	move.w	d0,-2(a5)
	addq.l	#2,a5
	moveq	#7,d0
	and.w	frame(pc),d0
	bne.s	.pitch
	move.w	(a5)+,d0
	add.w	(a5),d0
	cmp.w	#SPREAD,d0
	bls.s	.brth
	neg.w	(a5)
	add.w	(a5),d0
.brth	move.w	d0,-2(a5)
.pitch
	ifd	QUEUE
	move.l	a2,-(sp)		; a2 is the queue's write pointer while drawing
	lea	qbuf,a2			; the queue is empty and stopped here
	move.l	a2,qhead
	move.l	a2,qtail
	endc
	ifnd	NORENDER
	ifnd	NOCOMPOSE
	; --- rebuild one strip per frame
	lea	nextrow(pc),a0
	move.w	(a0),d0
	add.w	#ROWSZ,d0
	cmp.w	#NROWS*ROWSZ,d0
	bne.s	.rr
	moveq	#0,d0
.rr	move.w	d0,(a0)
	lea	rows(pc),a5
	add.w	d0,a5
	bsr	compose
	endc

	if	NFLY
	; --- erase the flyers drawn into this buffer two frames ago
	lea	-NFLY*4(a3),a4
	moveq	#NFLY-1,d7
	ifd	QUEUE
.erase	move.l	(a4)+,a0
	move.l	#$01000000,(a2)+	; D only, minterm 0
	lea	16(a2),a2		; masks and C, B, A pointers: not used
	move.l	a0,(a2)+
	addq.l	#6,a2
	move.w	#BPR-4,(a2)+
	move.w	#BLTSZ,(a2)+
	QKICK
	dbf	d7,.erase
	else
	WAITBLIT
	move.l	#$01000000,bltcon0(a6)	; D only, minterm 0
	move.w	#BPR-4,bltdmod(a6)
.erase	move.l	(a4)+,a0
	WAITBLIT
	move.l	a0,bltdpt(a6)
	move.w	#BLTSZ,bltsize(a6)
	dbf	d7,.erase
	endc
	endc

	; --- copy the five strips: draws the formation and erases its past
	lea	rows(pc),a5
	moveq	#NROWS-1,d7
	ifnd	QUEUE
	WAITBLIT
	moveq	#-1,d0
	move.l	d0,bltafwm(a6)
	endc
.row	move.w	r_x(a5),d0
	add.w	form(pc),d0
	move.w	r_y(a5),d1
	mulu	#ROWB,d1
	moveq	#15,d4
	and.w	d0,d4
	ror.w	#4,d4
	or.w	#$09f0,d4		; D = A
	swap	d4
	clr.w	d4			; bltcon0:bltcon1
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	lea	(a3,d1.l),a1
	moveq	#(GUARD+PLAYW+16)/8,d3
	sub.w	d0,d3
	lsr.w	#1,d3			; words left before the panel
	move.w	r_w(a5),d0
	move.w	d0,d2
	cmp.w	d3,d0
	bls.s	.fits
	move.w	d3,d0			; drop the strip's blank tail
.fits	sub.w	d0,d2
	add.w	d2,d2			; strip modulo
	moveq	#BPR,d3
	sub.w	d0,d3
	sub.w	d0,d3			; screen modulo
	or.w	#(16*4)<<6,d0
	ifd	QUEUE
	move.l	d4,(a2)+
	moveq	#-1,d1
	move.l	d1,(a2)+
	addq.l	#8,a2			; C and B pointers: not used
	move.l	(a5),(a2)+
	move.l	a1,(a2)+
	addq.l	#4,a2
	move.w	d2,(a2)+
	move.w	d3,(a2)+
	move.w	d0,(a2)+
	QKICK
	else
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.w	d2,bltamod(a6)
	move.w	d3,bltdmod(a6)
	move.l	(a5),bltapt(a6)
	move.l	a1,bltdpt(a6)
	move.w	d0,bltsize(a6)
	endc
	lea	ROWSZ(a5),a5
	dbf	d7,.row

	if	NFLY
	; --- move and draw the flyers
	move.w	frame(pc),d6		; wing flap: frame pointer 0 or 1
	lsr.w	#2,d6
	and.w	#4,d6
	lea	-NFLY*4(a3),a4
	lea	bobs(pc),a5
	moveq	#NFLY-1,d7
	ifnd	QUEUE
	WAITBLIT
	move.l	#$ffff0000,bltafwm(a6)	; mask out the second mask word
	move.l	#(BPR-4)<<16+$fffe,bltcmod(a6)	; C modulo, B modulo -2
	move.l	#$fffe<<16+BPR-4,bltamod(a6)	; A modulo -2, D modulo
	endc
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
	moveq	#-1,d2			; first word mask: whole image, unless
	cmp.w	#GUARD+PLAYW-16,d0	; the second word would be the gap
	bls.s	.noclip
	lsl.w	d4,d2			; then drop the columns that shift into it
.noclip	ror.w	#4,d4			; shift in bits 15-12
	lsr.w	#3,d0
	and.w	#$fffe,d0
	add.w	d0,d1
	lea	(a3,d1.l),a1		; destination word
	move.w	d4,d5
	or.w	#$0fca,d5		; A=mask B=image C=D=screen, cookie cut
	swap	d5
	move.w	d4,d5			; bltcon0:bltcon1
	move.l	a1,(a4)+		; remember for the erase pass
	ifd	QUEUE
	move.l	d5,(a2)+
	move.w	d2,(a2)+
	clr.w	(a2)+			; mask out the second mask word
	move.l	a1,(a2)+
	move.l	a0,(a2)+
	lea	128(a0),a0
	move.l	a0,(a2)+
	move.l	a1,(a2)+
	move.l	#(BPR-4)<<16+$fffe,(a2)+	; C modulo, B modulo -2
	move.l	#$fffe<<16+BPR-4,(a2)+	; A modulo -2, D modulo
	move.w	#BLTSZ,(a2)+
	QKICK
	else
	WAITBLIT
	move.l	d5,bltcon0(a6)
	move.w	d2,bltafwm(a6)
	move.l	a0,bltbpt(a6)
	lea	128(a0),a0
	move.l	a0,bltapt(a6)
	move.l	a1,bltcpt(a6)
	move.l	a1,bltdpt(a6)
	move.w	#BLTSZ,bltsize(a6)
	endc
	dbf	d7,.draw
	endc
	endc				; NORENDER

	ifd	QUEUE
	move.l	(sp)+,a2
	else
	WAITBLIT
	endc
	if	LOGIC
	move.w	#LOGIC-1,d0		; the game logic's stand-in
.think	dbf	d0,.think
	endc
	ifd	QUEUE
.drain	tst.b	qidle			; set by the interrupt after the last blit
	beq.s	.drain
	endc
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
	bsr	snd_stop
	move.w	#$7fff,d0
	move.w	d0,intena(a6)
	move.w	d0,intreq(a6)
	move.w	d0,dmacon(a6)
	move.l	(sp)+,$78.w
	move.l	(sp)+,$6c.w
	move.w	(sp)+,d6		; kept clear of the library call's scratch registers
	move.w	(sp)+,d7
	move.l	(sp)+,d0		; back to user mode and the system's stack
	move.l	a6,a4
	move.l	4.w,a6
	jsr	UserState(a6)
	move.l	a4,a6
	move.l	(sp)+,a5
	move.l	gb_copinit(a5),cop1lc(a6)
	move.l	gb_LOFlist(a5),cop2lc(a6)
	or.w	#$8000,d6
	or.w	#$c000,d7
	move.w	d6,dmacon(a6)
	move.w	d7,intena(a6)
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
	include	"measure6.i"
	endc
	moveq	#0,d0
	rts

;----------------------------------------------------------------------
; a5 = formation row: rebuild its strip at the current pitch and flap,
; and work out where the strip goes on screen. Keeps d5, a3, a5; with
; QUEUE, a2 is the queue's write pointer and d6 is used.
compose:
	move.l	(a5),a1
	move.w	r_w(a5),d0
	move.w	d0,d1
	or.w	#(16*4)<<6,d1
	ifd	QUEUE
	move.l	#$01000000,(a2)+	; clear the strip
	lea	16(a2),a2
	move.l	a1,(a2)+
	addq.l	#6,a2
	clr.w	(a2)+
	move.w	d1,(a2)+
	QKICK
	else
	WAITBLIT
	move.l	#$01000000,bltcon0(a6)	; clear the strip
	move.w	#0,bltdmod(a6)
	move.l	a1,bltdpt(a6)
	move.w	d1,bltsize(a6)
	endc

	moveq	#16,d2
	add.w	form+4(pc),d2		; d2 = column pitch
	move.w	d2,d1
	mulu	#9,d1
	lsr.w	#1,d1			; half the width of 10 columns
	move.w	r_first(a5),d3
	mulu	d2,d3
	sub.w	d1,d3
	add.w	#CX-8-16,d3		; -16: the strip starts with a blank word
	move.w	d3,r_x(a5)
	move.w	r_idx(a5),d3		; rows spread a quarter as much
	move.w	form+4(pc),d1
	mulu	d3,d1
	lsr.w	#2,d1
	lsl.w	#4,d3
	add.w	d3,d1
	add.w	#FY,d1
	move.w	d1,r_y(a5)

	move.l	r_gfx(a5),a0		; wings open, closed frame follows
	move.w	frame(pc),d1
	lsl.w	#4,d1
	and.w	#FRAME_SIZE,d1
	add.w	d1,a0
	add.w	d0,d0
	subq.w	#4,d0			; strip modulo for a 2-word blit
	ifd	QUEUE
	move.w	d0,d6
	else
	WAITBLIT
	move.l	#$ffff0000,bltafwm(a6)
	move.w	#-2,bltamod(a6)
	move.w	d0,bltcmod(a6)
	move.w	d0,bltdmod(a6)
	endc
	moveq	#16,d3			; pixel position in the strip
	move.w	r_ncols(a5),d7
	subq.w	#1,d7
.cell	move.w	d3,d0
	lsr.w	#3,d0
	and.w	#$fffe,d0
	lea	(a1,d0.w),a4
	moveq	#15,d4
	and.w	d3,d4
	ror.w	#4,d4
	or.w	#$0bfa,d4		; D = A or C
	swap	d4
	clr.w	d4
	ifd	QUEUE
	move.l	d4,(a2)+
	move.l	#$ffff0000,(a2)+
	move.l	a4,(a2)+
	addq.l	#4,a2
	move.l	a0,(a2)+
	move.l	a4,(a2)+
	move.w	d6,(a2)+
	addq.l	#2,a2
	move.w	#-2,(a2)+
	move.w	d6,(a2)+
	move.w	#BLTSZ,(a2)+
	QKICK
	else
	WAITBLIT
	move.l	d4,bltcon0(a6)
	move.l	a0,bltapt(a6)
	move.l	a4,bltcpt(a6)
	move.l	a4,bltdpt(a6)
	move.w	#BLTSZ,bltsize(a6)
	endc
	add.w	d2,d3
	dbf	d7,.cell
	rts

; d0 = buffer to display
show:	add.l	#VISIBLE,d0
	lea	cop_bpl+2,a0
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

; a1 = buffer: draw the panel's fixed text and the lives icons
panel:	move.l	a1,a5
	lea	labels(pc),a0
.label	move.w	(a0)+,d0		; colour, 0 ends
	beq.s	.icons
	move.l	a5,a1
	add.l	(a0)+,a1
	bsr.s	print
	move.l	a0,d0			; text is padded to even
	addq.l	#1,d0
	bclr	#0,d0
	move.l	d0,a0
	bra.s	.label
.icons	lea	PANEL+232*ROWB,a1
	add.l	a5,a1
	bsr.s	.icon
	lea	PANEL+232*ROWB+2,a1
	add.l	a5,a1
.icon	lea	enemies+GFX_FIGHTER+6*FRAME_SIZE,a0
	moveq	#16*4-1,d1
.word	move.w	(a0)+,(a1)
	lea	BPR(a1),a1
	dbf	d1,.word
	rts

; a0 = ASCII text, 0 ends  a1 = screen byte of the first char  d0 = colour
; Only the planes set in the colour are written, so a cell must keep its
; colour. Leaves a0 after the terminator. Trashes d1-d2/d4, a1, a4.
print:	moveq	#0,d1
	move.b	(a0)+,d1
	beq.s	.done
	lsl.w	#3,d1
	lea	font-32*8,a4
	add.w	d1,a4
	moveq	#0,d4			; plane
.plane	btst	d4,d0
	beq.s	.skip
	moveq	#8-1,d2
.row	move.b	(a4)+,(a1)
	lea	ROWB(a1),a1
	dbf	d2,.row
	subq.l	#8,a4
	lea	-8*ROWB(a1),a1
.skip	lea	BPR(a1),a1
	addq.w	#1,d4
	cmp.w	#4,d4
	bne.s	.plane
	lea	1-4*BPR(a1),a1		; next character cell
	bra.s	print
.done	rts

; a5 = bullet x,y  a0 = sprite  d5 = ship x
bullet:	subq.w	#6,2(a5)
	bpl.s	.fly
	move.w	d5,(a5)
	move.w	#SHIPY-16,2(a5)
.fly	move.w	(a5)+,d0
	move.w	(a5)+,d1

; d0 = x, d1 = y, a0 = 16-line sprite: write its two control words
setspr:	add.w	#$80,d0
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

; set the WAIT line bit of the entry \1 lines below the first one to \2,
; in both copies of the table. d0 = first entry, a1 = stars.
FLAG	macro
	moveq	#0,d1
	move.b	d0,d1
	add.b	#\1,d1
	mulu	#STARSZ,d1
	move.b	#\2,8(a1,d1.w)
	move.b	#\2,8(a2,d1.w)
	endm

	include	"sound.s"

	ifd	QUEUE
; level 3: the blitter has finished (or QKICK says so), or the vertical blank
lev3:	btst	#6,CUSTOM+intreqr+1
	beq.s	vbi
	movem.l	a0/a6,-(sp)
	lea	CUSTOM,a6
	move.w	#$0040,intreq(a6)
	move.l	qhead(pc),a0
	cmp.l	qtail(pc),a0
	beq.s	.empty
	move.l	(a0)+,bltcon0(a6)	; and bltcon1
	move.l	(a0)+,bltafwm(a6)	; and the last word mask
	move.l	(a0)+,bltcpt(a6)
	move.l	(a0)+,bltbpt(a6)
	move.l	(a0)+,bltapt(a6)
	move.l	(a0)+,bltdpt(a6)
	move.l	(a0)+,bltcmod(a6)	; and B
	move.l	(a0)+,bltamod(a6)	; and D
	move.w	(a0)+,bltsize(a6)	; go
	move.l	a0,qhead
	movem.l	(sp)+,a0/a6
	rte
.empty	st	qidle
	movem.l	(sp)+,a0/a6
	rte
	endc

vbi:	movem.l	d0-d3/a0-a2,-(sp)
	lea	stars,a1
	lea	STARCPY(a1),a2
	lea	frame(pc),a0
	addq.w	#1,(a0)
	move.w	(a0)+,d3
	move.w	(a0),d0			; table entry shown on the first line
	moveq	#1-1,d2			; scroll 1 line a frame, 3 in bursts
	btst	#7,d3
	beq.s	.step
	moveq	#3-1,d2
.step	subq.b	#1,d0			; stars move down: start one entry earlier
	FLAG	TO128,$80		; this entry is now on line 128
	FLAG	TO256,$00		; and this one on line 256
	dbf	d2,.step
	move.w	d0,starpos
	mulu	#STARSZ,d0
	add.l	a1,d0
	move.l	d0,CUSTOM+cop2lc	; the copper jumps here on line 43

	move.l	fadeptr(pc),a0		; this frame's fade steps
.fade	move.w	(a0)+,d0		; colour word in the table, negative ends
	bmi.s	.faded
	move.w	(a0)+,d1
	move.w	d1,(a1,d0.w)
	move.w	d1,(a2,d0.w)
	bra.s	.fade
.faded	addq.w	#1,d0			; -1 = end of frame, -2 = end of schedule
	beq.s	.next
	lea	starev,a0
.next	move.l	a0,fadeptr
	move.w	#$0020,CUSTOM+intreq
	movem.l	(sp)+,d0-d3/a0-a2
	rte

;----------------------------------------------------------------------
frame:	dc.w	0
starpos: dc.w	0			; must follow frame
fadeptr: dc.l	starev
ship:	dc.w	SHIPX/2,2		; x, dx
	dc.w	0,100,0,220		; bullets: x, y
form:	dc.w	SWAY/2,1		; sway, direction
	dc.w	0,1			; spread, direction
nextrow: dc.w	0
stale:	dc.w	2			; buffers whose score is out of date
score:	dc.b	0,0,0,0			; BCD, 6 digits in the first 3 bytes
points:	dc.b	0,0,$30,0
digits:	dc.b	"000000",0
	even

LABEL	macro				; colour, row, column, text
	dc.w	\1
	dc.l	PANEL+\2*ROWB+\3
	dc.b	\4,0
	even
	endm

labels:	LABEL	2,8,0,"HIGH SCORE"
	LABEL	1,18,2,"020000"
	LABEL	2,40,0,"1UP"
	LABEL	3,216,0,"SHIPS"
	dc.w	0
	ifd	QUEUE
qhead:	dc.l	0			; next blit to start
qtail:	dc.l	0			; end of the queued blits
qidle:	dc.b	$ff,0			; set when the interrupt found the queue empty
	endc
beats:	dc.b	16,16,2*$0f		; shot
	dc.b	37,37,2*$03		; bee hit
	dc.b	53,53,2*$02		; butterfly hit
	dc.b	97,97,2*$04		; boss hit, first
	dc.b	101,50,2*$01		; boss hit, second
	dc.b	211,100,2*$13		; dive
	dc.b	251,200,s_bang		; fighter explosion
	dc.b	0
	even
	ifd	MEASURE
fstart:	dc.w	0
stats:	dc.w	0			; worst frame, raster lines
	dc.l	0			; total raster lines
	dc.w	0			; frames drawn
tickstats: dc.w	0			; worst sound tick, colour clocks
	dc.l	0			; total
	dc.w	0			; ticks
	endc
	ifd	SNDTEST
testvars: dc.w	0			; ticks so far
	dc.l	testscript,testlog
testscript:
	include	"sndtest_script.i"
	endc
sprtab:	dc.l	sprship,sprbul1,sprbul2
	dc.l	sprnull,sprnull,sprnull,sprnull,sprnull
gfxname: dc.b	"graphics.library",0
	even

ROW	macro				; strip, image set, width, columns, first, row
	dc.l	\1,enemies+\2+6*FRAME_SIZE
	dc.w	\3,\4,\5,\6,0,0
	endm

rows:	ROW	strip0,GFX_BOSS,W4,4,3,0
	ROW	strip1,GFX_BUTTERFLY,W8,8,1,1
	ROW	strip2,GFX_BUTTERFLY,W8,8,1,2
	ROW	strip3,GFX_BEE,W10,10,0,3
	ROW	strip4,GFX_BEE,W10,10,0,4

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

bobs:	rept	NFLY/10
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
	dc.w	$0104,$001b		; sprites 0-5 in front, 6-7 (stars) behind
	dc.w	$0108,ROWB-40,$010a,ROWB-40
cop_bpl: dc.w	$00e0,0,$00e2,0,$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0,$00ec,0,$00ee,0
cop_spr: dc.w	$0120,0,$0122,0,$0124,0,$0126,0
	dc.w	$0128,0,$012a,0,$012c,0,$012e,0
	dc.w	$0130,0,$0132,0,$0134,0,$0136,0
	dc.w	$0138,0,$013a,0,$013c,0,$013e,0
	COPPER_PALETTE
	dc.w	$2bdf,$fffe		; end of the line above the display
	dc.w	$017e,$0000,$017c,$8000	; arm sprite 7 by hand: one pixel
	dc.w	$008a,$0000		; continue in the star table (cop2lc)

stars:	incbin	"stars.bin"
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
font:	incbin	"font.bin"
snd_waves: incbin "snd_chip.bin",0,448
snd_noise: incbin "snd_chip.bin",448

	section	fade,data
starev:	incbin	"starev.bin"

;----------------------------------------------------------------------
	section	screens,bss_c

; strip width in words: blank word + columns at the widest pitch + slack
W4	equ	(16+3*(16+SPREAD)+16+15)/16+1
W8	equ	(16+7*(16+SPREAD)+16+15)/16+1
W10	equ	(16+9*(16+SPREAD)+16+15)/16+1

bssmem:	ds.l	NFLY			; erase list of screen1
screen1: ds.b	SCRSIZE
	ds.l	NFLY			; erase list of screen2
screen2: ds.b	SCRSIZE
strip0:	ds.w	W4*16*4
strip1:	ds.w	W8*16*4
strip2:	ds.w	W8*16*4
strip3:	ds.w	W10*16*4
strip4:	ds.w	W10*16*4
BSSSIZE	equ	*-bssmem

; state only the CPU touches: fast RAM if the machine has any
	section	work,bss
snd_state: ds.b	S_SIZE
	ifd	QUEUE
qbuf:	ds.b	Q_SIZE*Q_MAX
	endc
	section	screens,bss_c
	ifd	SNDTEST
testlog: ds.b	SNDTEST*12
	endc
