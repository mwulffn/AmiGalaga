; Stars: the scrolling, fading starfield.
;
; One hardware sprite (sprite 7, a single pixel) is moved and recoloured
; on every raster line by a copper table, so each line can hold one star
; of any colour. The table has no line numbers in it: every entry ends
; with "wait for the end of this line". Scrolling is therefore just
; starting the table at a different entry each frame.
;
; Each star fades between off and full brightness on its own period. The
; fades are a schedule of (colour word, new colour) pairs, a few per
; frame, written into the table here; the schedule loops.
;
; How fast it scrolls is the arcade's: a line per arcade frame at first,
; more on later stages, standing still while the fighter is gone.
;
; The one thing that needs patching for the scroll: a copper wait cannot
; ignore bit 7 of the line number, so the entries that currently fall on
; raster lines 128-255 carry that bit. Scrolling by n lines moves 2n
; entries across those boundaries.
;
; Behind them is a second layer, the far stars: fewer, dim, and scrolling a
; quarter as fast. They cannot be in the same table, which scrolls as one,
; so they are an ordinary sprite (sprite 6): a list of one-line images, one
; for each star, which the hardware shows from the top down. When they move
; a line, every star's place in the list is written again; the one that
; leaves at the bottom comes in at the top, and the list starts with it from
; then on. They share the near stars' three colours: the near ones use the
; first, which the table changes on every line, and the far ones the other
; two, which stay as they are.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"stars2.i"

	xdef	StarsInit
	xdef	FarList
	xdef	StarsStage
	xdef	StarsTick
	xdef	StarsVBlank

STAR_ENTRY	equ	12			; a table entry: move position, move colour, wait
STAR_LINES	equ	256			; lines in the table, which is stored twice over
STAR_COPY	equ	STAR_LINES*STAR_ENTRY	; from an entry to its second copy
STAR_WAIT	equ	8			; offset of an entry's wait: its first byte is the line bits
LINE_BIT7	equ	$80
TO_LINE_128	equ	128-DISPLAY_TOP		; entries from the first line to raster line 128
TO_LINE_256	equ	256-DISPLAY_TOP
FADE_END	equ	-2			; schedule: -1 ends a frame, -2 ends the schedule
COPPER_END	equ	$fffffffe
STAR_SPEED	equ	$40			; a line per arcade frame, in 64ths: the speed on the first stages
FASTEST_STAGE	equ	16			; from this stage on they go no faster
STAGE_STEPS	equ	$70			; stage * 4, masked with this, is added to the speed
CARRY_BITS	equ	6
TITLE_SPEED	equ	16			; 64ths of a line per arcade frame while no game is on: 15 lines a second
BACK_LINES	equ	3			; lines per arcade frame when they run backwards
CARRY_MASK	equ	(1<<CARRY_BITS)-1
; the far stars
FAR_SLOWER	equ	4			; lines the near stars scroll for one of theirs
FAR_PIXEL	equ	$8000			; a star: the sprite's leftmost pixel
RASTER_LINES	equ	256			; a sprite's line has a ninth bit from here on
SPR_START8	equ	4			; in a sprite's second control word: the ninth bit of its first line,
SPR_STOP8	equ	2			;   and of the line after its last
; a far star in FarStars
	rsreset
fr_line		rs.b	1			; its line at rest, 0-255
fr_x		rs.b	1			; its sprite x, halved
fr_plane	rs.w	1			; the word for the sprite's first plane: FAR_PIXEL for the brighter colour
fr_SIZEOF	rs.b	0

; Set the line bit of the entry \1 lines below the first one to \2, in both
; copies of the table. d0 = first entry, a1 = table, a2 = its second copy.
SETLINE	macro
	moveq	#0,d1
	move.b	d0,d1
	add.b	#\1,d1
	mulu.w	#STAR_ENTRY,d1
	move.b	#\2,STAR_WAIT(a1,d1.w)
	move.b	#\2,STAR_WAIT(a2,d1.w)
	endm

	section	code,code

;--
; StarsInit
; Start the stars: one line a frame, from the top of the table; the far ones at rest.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d2, a0-a2
StarsInit:
	clr.w	StarFirst(a5)
	clr.w	StarSpeed(a5)
	clr.b	StarNow(a5)
	clr.b	StarCarry(a5)
	move.b	#STAR_SPEED,StarTarget(a5)
	move.l	#StarFades,StarFade(a5)
	move.l	#StarTable,cop2lc(a6)
	clr.b	FarCarry(a5)
	clr.b	FarOffset(a5)
	move.b	#FAR_STARS,FarFirst(a5)
	bra	FarPlace

;--
; StarsStage
; Set the speed the stars work up to for a stage: faster every fourth stage, up to stage 16.
; In:       d0.w = stage, a5 = state
; Out:      -
; Clobbers: d1
StarsStage:
	moveq	#FASTEST_STAGE,d1
	cmp.w	d1,d0
	bcc	.Speed
	move.w	d0,d1
.Speed	lsl.w	#2,d1
	and.w	#STAGE_STEPS,d1
	add.w	#STAR_SPEED,d1
	move.b	d1,StarTarget(a5)
	rts

;--
; StarsTick
; One arcade frame of the stars' speed. While no game is on they drift slowly. In a game
; it is as the arcade has it: they stand still while the
; fighter is not on the screen, and work back up to speed, a 64th of a line per frame more
; each frame, when it returns.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d1
StarsTick:
	tst.b	StarBack(a5)
	beq	.Forward
	subq.w	#BACK_LINES,StarSteps(a5)	; the fighter is being pulled up: they run backwards
	rts
.Forward
	tst.b	Mode(a5)			; the title, the options, the best scores: slowly
	beq	.Game
	moveq	#TITLE_SPEED,d0
	bra	.Steady
.Game	move.b	PlayerState(a5),d0
	beq	.Moving				; PS_PLAYING
	cmp.b	#PS_READY,d0
	beq	.Moving
	clr.b	StarNow(a5)
	clr.b	StarCarry(a5)
	rts
.Moving	move.b	StarNow(a5),d0
	cmp.b	StarTarget(a5),d0
	beq	.Steady
	addq.b	#1,d0
	move.b	d0,StarNow(a5)
.Steady	add.b	StarCarry(a5),d0
	moveq	#CARRY_MASK,d1
	and.b	d0,d1
	move.b	d1,StarCarry(a5)
	lsr.b	#CARRY_BITS,d0
	ext.w	d0
	add.w	d0,StarSteps(a5)
	rts

;--
; StarsVBlank
; Once per frame, from the vertical blank: scroll and fade.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d2, a0-a2
StarsVBlank:
	lea	StarTable,a1
	lea	STAR_COPY(a1),a2
	move.w	StarFirst(a5),d0
	move.w	StarSpeed(a5),d2
	beq	.Still
	bmi	.Back
	subq.w	#1,d2
.Step	subq.b	#1,d0				; stars move down: start one entry earlier
	SETLINE	TO_LINE_128,LINE_BIT7		; this entry is now on line 128
	SETLINE	TO_LINE_256,0			; and this one on line 256
	dbf	d2,.Step
	bra	.Moved
.Back	neg.w	d2
	subq.w	#1,d2
.Up	SETLINE	TO_LINE_128,0			; stars move up: this entry leaves line 128
	SETLINE	TO_LINE_256,LINE_BIT7		; and this one comes onto line 255
	addq.b	#1,d0
	dbf	d2,.Up
.Moved	move.w	d0,StarFirst(a5)
.Still	mulu.w	#STAR_ENTRY,d0
	add.l	a1,d0
	move.l	d0,cop2lc(a6)			; the copper jumps here above the display

	move.l	StarFade(a5),a0			; this frame's fade steps
.Fade	move.w	(a0)+,d0			; colour word in the table, negative ends
	bmi	.Faded
	move.w	(a0)+,d1
	move.w	d1,(a1,d0.w)
	move.w	d1,(a2,d0.w)
	bra	.Fade
.Faded	cmp.w	#FADE_END,d0
	bne	.Next
	lea	StarFades,a0
.Next	move.l	a0,StarFade(a5)

	; the far stars: a line for every FAR_SLOWER the near ones scroll. Downwards only:
	; while the near ones run backwards these stand still.
	move.w	StarSpeed(a5),d0
	ble	.Done
	add.b	FarCarry(a5),d0
	cmp.b	#FAR_SLOWER,d0
	bcs	.Kept
.Line	subq.b	#FAR_SLOWER,d0
	addq.b	#1,FarOffset(a5)
	bne	.Lower
	move.b	#FAR_STARS,FarFirst(a5)		; all the way round: the first is the highest again
	bra	.Lowered
	; the one above the highest so far is the lowest on the screen: has it left at the bottom?
.Lower	moveq	#0,d1
	move.b	FarFirst(a5),d1
	beq	.Lowered
	lsl.w	#2,d1				; * fr_SIZEOF
	lea	FarStars,a0
	move.b	fr_line-fr_SIZEOF(a0,d1.w),d2
	add.b	FarOffset(a5),d2
	bcc	.Lowered
	subq.b	#1,FarFirst(a5)			; then it has come in at the top, and is the highest
.Lowered
	cmp.b	#FAR_SLOWER,d0
	bcc	.Line
	move.b	d0,FarCarry(a5)
	bra	FarPlace
.Kept	move.b	d0,FarCarry(a5)
.Done	rts

;--
; FarPlace
; Write every far star's place into the sprite's list, from the highest on the screen down.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0-a2
FarPlace:
	lea	FarList,a0
	lea	FarStars,a1
	moveq	#0,d0
	move.b	FarFirst(a5),d0
	lsl.w	#2,d0				; * fr_SIZEOF
	add.w	d0,a1				; the highest; the others follow it, twice over
	lea	FarControl(pc),a2
	move.b	FarOffset(a5),d1
	add.b	#DISPLAY_TOP,d1			; from a line at rest to the low byte of its raster line
	moveq	#FAR_STARS-1,d2
.Star	moveq	#0,d0
	move.b	(a1)+,d0			; fr_line
	add.b	d1,d0
	move.b	d0,(a0)+			; first control word: the line, and x
	move.b	(a1)+,(a0)+
	add.w	d0,d0
	move.w	(a2,d0.w),(a0)+			; second: the line after, and both lines' ninth bits
	move.w	(a1)+,(a0)+			; first plane; the second always has the pixel
	addq.l	#2,a0
	dbf	d2,.Star
	rts

; A sprite's second control word for a one-line image, by the low byte of its raster line.
; The lines are DISPLAY_TOP to DISPLAY_TOP+255, so a low byte below DISPLAY_TOP is a line
; from RASTER_LINES on.
FarControl:
LINE	set	0
	rept	RASTER_LINES
	dc.w	((LINE+1)&$ff)<<8|((LINE<DISPLAY_TOP)&SPR_START8)|(((LINE<DISPLAY_TOP)|(LINE=RASTER_LINES-1))&SPR_STOP8)
LINE	set	LINE+1
	endr

	section	data,data

; generated by tools/make_stars.py: (offset of a colour word, new colour) pairs
StarFades:	incbin	"starev.bin"

; generated by tools/make_stars.py: the far stars in the order of their lines, twice over
FarStars:	incbin	"stars2.bin"

	section	chip_data,data_c

; generated by tools/make_stars.py: per line, sprite 7's position and colour, then a wait
StarTable:	incbin	"stars.bin"
	dc.l	COPPER_END

; sprite 6's list: for each far star two control words and its one line's two planes; the
; end is two words of nought
FarList:
	rept	FAR_STARS
	dc.w	0,0,0,FAR_PIXEL
	endr
	dc.w	0,0
