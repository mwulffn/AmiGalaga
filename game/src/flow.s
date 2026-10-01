; Flow: what happens between stages, as the arcade times it.
;
; The arcade's pauses are counts of a timer that steps every 32 frames.
;   A new game: PLAYER 1 and the start theme for 8 counts; then the first
;     stage's splash; then the fighter comes on, under PLAYER 1 and
;     STAGE 1, and after 3 counts is in play.
;   A stage's splash: STAGE n (or CHALLENGING STAGE and its tune) for 3
;     counts, while the badges for the stage number appear one every 8
;     frames with a click; then the stage is set up and its waves begin.
;   A stage cleared: 4 counts, then the next stage's splash.
;   A challenging stage cleared: its tune, NUMBER OF HITS, the number,
;     BONUS and the bonus (100 a hit), 3 counts apart; or for all 40,
;     PERFECT blinking and SPECIAL BONUS 10000 PTS.
;   A fighter lost: READY from when the next one is due until it is in
;     play; GAME OVER after the last.
; Here too: the high score, and an extra fighter at 20000, at 70000 and
; every 70000 after.
;
; Not built yet: the results after GAME OVER (shots, hits, ratio).

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	FlowInit
	xdef	FlowTick
	xref	StageInit
	xref	PlayerEnter
	xref	ScoreAdd
	xref	TextShow
	xref	TextHide

COUNT_FRAMES	equ	32			; arcade frames per count of FlowTimer
INTRO_PAUSE	equ	8			; counts PLAYER 1 shows at the start of a game
CLEARED_PAUSE	equ	4			;   after a stage is cleared
SPLASH_PAUSE	equ	3			;   STAGE n shows before the stage begins
RESULT_PAUSE	equ	3			;   between a challenging stage's result lines
RESULT_END	equ	6			;   its bonus shows
BADGE_FRAMES	equ	8			; arcade frames between badges appearing
BLINK_FRAMES	equ	16			; arcade frames between PERFECT going on and off
BLINKS		equ	7
CHALLENGE_MASK	equ	3			; a stage whose number ends in these two bits set is a challenging stage
ALL_HITS	equ	40
; FlowStep through a challenging stage's results
RS_TITLE	equ	0			; next: NUMBER OF HITS
RS_HITS		equ	1			; next: the number
RS_BONUS	equ	2			; next: BONUS, or PERFECT
RS_BLINK	equ	3			; BLINKS steps of PERFECT blinking
RS_VALUE	equ	RS_BLINK+BLINKS+1	; next: the bonus
RS_END		equ	RS_VALUE+1		; next: the next stage
; FlowText
FT_NONE		equ	0
FT_READY	equ	1
FT_OVER		equ	2
; where the text goes: column, row in the playfield's characters
OPENING_AT	equ	11
MESSAGE_COLUMN	equ	10
MESSAGE_ROW	equ	16
PLAYER_ROW	equ	14
WIDE_COLUMN	equ	5			; CHALLENGING STAGE, NUMBER OF HITS
BONUS_COLUMN	equ	8
BONUS_ROW	equ	19
SPECIAL_COLUMN	equ	2
PERFECT_ROW	equ	13
FIRST_BONUS	equ	$00020000		; the scores that bring an extra fighter, as decimal digits
SECOND_BONUS	equ	$00070000
BONUS_STEP	equ	$07			;   and every 70000 after, added to the ten-thousands
PERFECT_POINTS	equ	$00010000
NO_BONUS	equ	-1
FIRST_SCORE	equ	$00020000		; the high score to beat
; badge tiles: the top tile of each badge's first column
BADGE_1		equ	$36
BADGE_5		equ	$38
BADGE_10	equ	$3a			; 10, 20, 30 are 4 tiles apart
BADGE_50	equ	$46

	section	code,code

;--
; FlowInit
; A new game opens: PLAYER 1, the start theme, no fighter yet.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
FlowInit:
	move.b	#FL_INTRO,FlowState(a5)
	move.b	#INTRO_PAUSE,FlowTimer(a5)
	st	FirstStage(a5)
	clr.b	FlowText(a5)
	move.w	#FIRST_STAGE-1,Stage(a5)
	clr.b	BadgeCount(a5)
	clr.b	BadgeShown(a5)
	move.l	#FIRST_BONUS,NextBonus(a5)
	tst.l	HighScore(a5)
	bne	.High
	move.l	#FIRST_SCORE,HighScore(a5)
.High	move.b	#PS_ABSENT,PlayerState(a5)
	clr.b	InPlay(a5)
	moveq	#1,d0
	bsr	TextHide
	moveq	#2,d0
	bsr	TextHide
	lea	PlayerText(pc),a0
	moveq	#OPENING_AT,d1
	moveq	#MESSAGE_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#0,d0
	bsr	TextShow
	SOUND	SND_START
	rts

;--
; FlowTick
; One arcade frame of the game's flow.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
FlowTick:
	moveq	#COUNT_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Timed
	tst.b	FlowTimer(a5)
	beq	.Timed
	subq.b	#1,FlowTimer(a5)
.Timed	; the high score follows the score; a score past NextBonus brings a fighter
	move.l	Score(a5),d0
	cmp.l	HighScore(a5),d0
	bls	.Bonus
	move.l	d0,HighScore(a5)
.Bonus	cmp.l	NextBonus(a5),d0
	bcs	.Badges
	addq.b	#1,Lives(a5)
	SOUND	SND_EXTRA_FIGHTER
	move.l	#SECOND_BONUS,d0
	cmp.l	#FIRST_BONUS,NextBonus(a5)
	beq	.Next
	; + 70000, in decimal; past 990000 there are no more
	move.b	NextBonus+1(a5),d0
	moveq	#BONUS_STEP,d1
	and.b	#$ef,ccr
	abcd	d1,d0
	scs	d1
	and.l	#$ff,d0
	swap	d0
	tst.b	d1
	beq	.Next
	moveq	#NO_BONUS,d0
.Next	move.l	d0,NextBonus(a5)

	; a new stage's badges appear one at a time
.Badges	move.b	BadgeShown(a5),d0
	cmp.b	BadgeCount(a5),d0
	bcc	.State
	subq.b	#1,BadgeWait(a5)
	bne	.State
	move.b	#BADGE_FRAMES,BadgeWait(a5)
	ext.w	d0
	lea	BadgeList(a5),a0
.Column	addq.w	#1,d0				; a badge is one column or two
	cmp.b	BadgeCount(a5),d0
	bcc	.Shown
	tst.b	(a0,d0.w)
	bpl	.Column
.Shown	move.b	d0,BadgeShown(a5)
	moveq	#CHALLENGE_MASK,d0		; no clicks before a challenging stage: it has its tune
	and.w	Stage(a5),d0
	subq.w	#CHALLENGE_MASK,d0
	beq	.State
	SOUND	SND_BADGE

.State	move.b	FlowState(a5),d0
	beq	Playing
	subq.b	#FL_CLEARED,d0
	bcs	.Intro
	beq	.Cleared
	subq.b	#FL_SPLASH-FL_CLEARED,d0
	bcs	Results
	beq	.Splash
	; FL_ENTER: once the fighter is in play the texts go
	cmp.b	#PS_PLAYING,PlayerState(a5)
	bne	.Done
	moveq	#1,d0
	bsr	TextHide
	bra	.Play
.Intro	tst.b	FlowTimer(a5)
	bne	.Done
	bra	Splash
.Cleared
	tst.b	FlowTimer(a5)
	bne	.Done
	moveq	#CHALLENGE_MASK,d0
	and.w	Stage(a5),d0
	subq.w	#CHALLENGE_MASK,d0
	bne	Splash
	; a challenging stage: its results, to the tune for all 40 or for fewer
	move.b	#FL_RESULTS,FlowState(a5)
	move.b	#RS_TITLE,FlowStep(a5)
	move.b	#RESULT_PAUSE,FlowTimer(a5)
	cmp.b	#ALL_HITS,FlyingHits(a5)
	beq	.Perfect
	SOUND	SND_RESULTS
	rts
.Perfect
	SOUND	SND_PERFECT
.Done	rts
	; FL_SPLASH: the stage is set up and begins
.Splash	tst.b	FlowTimer(a5)
	bne	.Done
	move.w	Stage(a5),d0
	bsr	StageInit
	LOG	#STAGE_BEGUN,Stage+1(a5)
	tst.b	FirstStage(a5)
	beq	.Play
	; a game's first stage: the fighter comes on under PLAYER 1 and STAGE 1
	clr.b	FirstStage(a5)
	bsr	PlayerEnter
	lea	PlayerText(pc),a0
	moveq	#MESSAGE_COLUMN,d1
	moveq	#PLAYER_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#1,d0
	bsr	TextShow
	move.b	#FL_ENTER,FlowState(a5)
	rts
.Play	moveq	#0,d0
	bsr	TextHide
	clr.b	FlowText(a5)
	move.b	#FL_PLAY,FlowState(a5)
	rts

;--
; Playing
; A stage is running: show the fighter's messages, and see if the stage is cleared.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
Playing:
	moveq	#FT_NONE,d4
	move.b	PlayerState(a5),d0
	cmp.b	#PS_RETURNING,d0
	beq	.Ready
	cmp.b	#PS_READY,d0
	bne	.Over
.Ready	moveq	#FT_READY,d4
.Over	cmp.b	#PS_OVER,d0
	bne	.Text
	moveq	#FT_OVER,d4
.Text	cmp.b	FlowText(a5),d4
	beq	.Stage
	move.b	d4,FlowText(a5)
	bne	.Show
	moveq	#0,d0
	bsr	TextHide
	bra	.Stage
.Show	lea	ReadyText(pc),a0
	subq.b	#FT_READY,d4
	beq	.Line
	lea	OverText(pc),a0
.Line	moveq	#MESSAGE_COLUMN,d1
	moveq	#MESSAGE_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#0,d0
	bsr	TextShow

	; cleared: every wave in, nothing of it left, and the fighter there to see it
.Stage	tst.b	WavesIn(a5)
	beq	.Busy
	tst.b	Alive(a5)
	bne	.Busy
	cmp.b	#PS_PLAYING,PlayerState(a5)
	bne	.Busy
	lea	Blasts(a5),a0
	moveq	#BLASTS-1,d0
.Blast	tst.b	bl_live(a0)
	bne	.Busy
	lea	bl_SIZEOF(a0),a0
	dbf	d0,.Blast
	lea	Flights(a5),a0
	moveq	#FLIGHT_SLOTS-1,d0
.Flight	moveq	#1<<FLB_ACTIVE|1<<FLB_LANDED,d1
	and.b	fl_flags(a0),d1
	bne	.Busy
	lea	fl_SIZEOF(a0),a0
	dbf	d0,.Flight
	move.b	#FL_CLEARED,FlowState(a5)
	move.b	#CLEARED_PAUSE,FlowTimer(a5)
.Busy	rts

;--
; Splash
; The next stage is announced: its number, its text, its badges.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
Splash:	addq.w	#1,Stage(a5)
	move.b	#FL_SPLASH,FlowState(a5)
	move.b	#SPLASH_PAUSE,FlowTimer(a5)
	moveq	#1,d0
	bsr	TextHide
	moveq	#2,d0
	bsr	TextHide

	; The badges, left to right: a 50 for each 50, then the tens (40 is a 30 and a 10),
	; a 5, then the ones. A column each for 1 and 5, two for the others.
	lea	BadgeList(a5),a0
	move.l	a0,a1
	move.w	Stage(a5),d0
.Fifty	cmp.w	#50,d0
	bcs	.Tens
	sub.w	#50,d0
	moveq	#BADGE_50,d1
	bsr	Wide
	bra	.Fifty
.Tens	ext.l	d0
	divu.w	#10,d0				; d0 = ones : tens
	cmp.w	#4,d0
	bne	.Ten
	moveq	#BADGE_10+2*4,d1		; the 30
	bsr	Wide
	moveq	#1,d2
	bra	.Lower
.Ten	move.w	d0,d2
	beq	.Ones
.Lower	lsl.w	#2,d2
	moveq	#BADGE_10-4,d1
	add.w	d2,d1
	bsr	Wide
.Ones	swap	d0
	cmp.w	#5,d0
	bcs	.One
	subq.w	#5,d0
	moveq	#BADGE_5,d1
	bsr	Narrow
.One	subq.w	#1,d0
	bcs	.Listed
	moveq	#BADGE_1,d1
	bsr	Narrow
	bra	.One
.Listed	sub.l	a0,a1
	move.w	a1,d0
	move.b	d0,BadgeCount(a5)
	clr.b	BadgeShown(a5)
	move.b	#BADGE_FRAMES,BadgeWait(a5)

	moveq	#CHALLENGE_MASK,d0
	and.w	Stage(a5),d0
	subq.w	#CHALLENGE_MASK,d0
	bne	.Number
	SOUND	SND_CHALLENGE
	lea	ChallengeText(pc),a0
	moveq	#WIDE_COLUMN,d1
	bra	.Text
	; STAGE and the number
.Number	lea	TextBuf(a5),a1
	lea	StageText(pc),a0
	bsr	Copy
	move.w	Stage(a5),d0
	bsr	Decimal
	clr.b	(a1)
	lea	TextBuf(a5),a0
	moveq	#MESSAGE_COLUMN,d1
.Text	moveq	#MESSAGE_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#0,d0
	bra	TextShow

;--
; Wide
; Add a two-column badge to the list, if there is room.
; In:       a1 = the list's end, a0 = its start, d1.b = the badge's first tile
; Out:      a1 = the list's end
; Clobbers: d1, d3
Wide:	bsr	Narrow
	addq.b	#2,d1
	bclr	#BADGEB_FIRST,d1
	bra	Second

;--
; Narrow
; Add a badge's first column to the list, if there is room.
; In:       a1 = the list's end, a0 = its start, d1.b = the column's top tile
; Out:      a1 = the list's end, d1.b = the tile with its first-column mark
; Clobbers: d3
Narrow:	bset	#BADGEB_FIRST,d1
	; falls through

;--
; Second
; Add a column to the list, if there is room.
; In:       a1 = the list's end, a0 = its start, d1.b = what to add
; Out:      a1 = the list's end
; Clobbers: d3
Second:	move.l	a1,d3
	sub.l	a0,d3
	cmp.w	#BADGE_PLACES,d3
	bcc	.Full
	move.b	d1,(a1)+
.Full	rts

;--
; Copy
; Copy a text without its terminator.
; In:       a0 = the text, 0 ends, a1 = where to
; Out:      a1 = after the copy
; Clobbers: a0
Copy:	tst.b	(a0)
	beq	.End
	move.b	(a0)+,(a1)+
	bra	Copy
.End	rts

;--
; Decimal
; Write a number as text, without leading zeros.
; In:       d0.w = the number, 0 to 999, a1 = where to
; Out:      a1 = after it
; Clobbers: d0-d1
Decimal:
	ext.l	d0
	divu.w	#100,d0
	move.w	d0,d1				; hundreds
	beq	.Tens
	add.b	#'0',d0
	move.b	d0,(a1)+
.Tens	clr.w	d0
	swap	d0
	divu.w	#10,d0
	tst.w	d1
	bne	.Ten
	tst.w	d0
	beq	.Ones
.Ten	add.b	#'0',d0
	move.b	d0,(a1)+
.Ones	swap	d0
	add.b	#'0',d0
	move.b	d0,(a1)+
	rts

;--
; Results
; A challenging stage's results, a line at a time.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
Results:
	moveq	#0,d4
	move.b	FlowStep(a5),d4
	cmp.b	#RS_BLINK,d4
	bcs	.Timed
	cmp.b	#RS_BLINK+BLINKS,d4
	bcc	.Timed
	; PERFECT goes on and off every BLINK_FRAMES, ending on
	moveq	#BLINK_FRAMES-1,d0
	and.w	ArcadeFrame(a5),d0
	bne	.Done
	addq.b	#1,FlowStep(a5)
	btst	#0,d4				; RS_BLINK is odd: odd steps show it
	beq	.Off
	lea	PerfectText(pc),a0
	moveq	#MESSAGE_COLUMN,d1
	moveq	#PERFECT_ROW,d2
	moveq	#TEXT_RED,d3
	moveq	#1,d0
	bsr	TextShow
	bra	.Blinked
.Off	moveq	#1,d0
	bsr	TextHide
.Blinked
	cmp.b	#RS_BLINK+BLINKS,FlowStep(a5)
	bne	.Done
	; and with the last, the special bonus
	lea	SpecialText(pc),a0
	moveq	#SPECIAL_COLUMN,d1
	moveq	#BONUS_ROW,d2
	moveq	#TEXT_YELLOW,d3
	moveq	#2,d0
	bsr	TextShow
	move.l	#PERFECT_POINTS,d2
	bra	.Award

.Timed	tst.b	FlowTimer(a5)
	bne	.Done
	move.b	#RESULT_PAUSE,FlowTimer(a5)
	addq.b	#1,FlowStep(a5)
	subq.b	#RS_HITS,d4
	bcs	.Title
	beq	.Hits
	subq.b	#RS_BONUS-RS_HITS,d4
	beq	.Bonus
	sub.b	#RS_VALUE-RS_BONUS,d4
	beq	.Value
	; RS_END: on to the next stage
	moveq	#0,d0
	bsr	TextHide
	bra	Splash
.Title	lea	HitsText(pc),a0
	bra	.Line0
	; NUMBER OF HITS and the number
.Hits	lea	TextBuf(a5),a1
	lea	HitsText(pc),a0
	bsr	Copy
	move.b	#' ',(a1)+
	moveq	#0,d0
	move.b	FlyingHits(a5),d0
	bsr	Decimal
	clr.b	(a1)
	lea	TextBuf(a5),a0
.Line0	moveq	#WIDE_COLUMN,d1
	moveq	#MESSAGE_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#0,d0
	bra	TextShow
.Bonus	cmp.b	#ALL_HITS,FlyingHits(a5)
	bne	.Plain
	move.b	#RS_BLINK,FlowStep(a5)
	rts
.Plain	move.b	#RS_VALUE,FlowStep(a5)
	lea	BonusText(pc),a0
	bra	BonusLine
	; BONUS and 100 for each hit
.Value	lea	TextBuf(a5),a1
	lea	BonusText(pc),a0
	bsr	Copy
	move.b	#' ',(a1)+
	move.b	#' ',(a1)+
	moveq	#0,d0
	move.b	FlyingHits(a5),d0
	beq	.Zero
	bsr	Decimal
	move.b	#'0',(a1)+
.Zero	move.b	#'0',(a1)+
	clr.b	(a1)
	lea	TextBuf(a5),a0
	bsr	BonusLine
	; the points: the hits as two decimal digits, times 100
	moveq	#0,d2
	move.b	FlyingHits(a5),d2
	divu.w	#10,d2
	move.w	d2,d0
	lsl.w	#4,d0
	swap	d2
	or.w	d0,d2
	lsl.w	#8,d2
	and.l	#$ffff,d2
.Award	bsr	ScoreAdd
	LOG	#STAGE_SCORE_HI,Score+2(a5)
	LOG	#STAGE_SCORE_LO,Score+3(a5)
	move.b	#RS_END,FlowStep(a5)
	move.b	#RESULT_END,FlowTimer(a5)
.Done	rts

;--
; BonusLine
; Show the results' bonus line.
; In:       a0 = its text, a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
BonusLine:
	moveq	#BONUS_COLUMN,d1
	moveq	#BONUS_ROW,d2
	moveq	#TEXT_CYAN,d3
	moveq	#2,d0
	bra	TextShow

PlayerText:
	dc.b	"PLAYER 1",0
ReadyText:
	dc.b	"READY",0
OverText:
	dc.b	"GAME OVER",0
StageText:
	dc.b	"STAGE ",0
ChallengeText:
	dc.b	"CHALLENGING STAGE",0
HitsText:
	dc.b	"NUMBER OF HITS",0
BonusText:
	dc.b	"BONUS",0
PerfectText:
	dc.b	"PERFECT",0
SpecialText:
	dc.b	"SPECIAL BONUS 10000 PTS",0
	even
