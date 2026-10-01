; Title: what shows when no game is on, and the options.
;
; The arcade's coin slot, its start buttons and its second player are gone.
; Instead:
;   The title: the game's name, START GAME and OPTIONS. The stick moves between
;     the two, the button takes one. Left alone for a while it gives way to
;   the best scores (five are kept, until power-off, without names so far),
;     which give way to the title again after a while or at a touch.
;   The options: how many fighters a game starts with (three, as the arcade
;     comes, or six) and the arcade's difficulty switch (its four ranks, which
;     pick the stage tables: see stage.s and dives.s). The stick moves between
;     the lines and changes the one it is on; the button on BACK goes back.
; A game that ends comes back here by way of GameInit.
;
; While any of this shows, the game runs with no stage and no fighter; the
; text is the game's own (text.s). Not here yet: an attract mode that plays
; by itself, and entering a name for a score.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	TitleShow
	xdef	TitleTick
	xdef	ScoresInit
	xdef	ScoresInsert
	xref	GameStart
	xref	TextShow
	xref	TextHide

; the stick and the button, as ReadPad gives them
PADB_UP		equ	0
PADB_DOWN	equ	1
PADB_LEFT	equ	2
PADB_RIGHT	equ	3
PADB_FIRE	equ	4
PAD_UP_DOWN	equ	1<<PADB_UP|1<<PADB_DOWN
JOYB_DOWN	equ	0			; joy1dat: this bit and the next differ when the stick is down,
JOYB_UP		equ	8			;   this one and the next when it is up
TITLE_FRAMES	equ	8*50			; the title gives way to the best scores after this long,
SCORES_FRAMES	equ	8*50			;   and they to the title
FIRST_SCORE	equ	$00020000		; every one of the best scores at the start, as the arcade's
SCORE_DIGITS	equ	6
; where things go, in characters of the playfield
HEAD_ROW	equ	8
TITLE_COLUMN	equ	9
START_COLUMN	equ	9
START_ROW	equ	16
OPTIONS_COLUMN	equ	10
OPTIONS_ROW	equ	19
ITEM_COLUMN	equ	5
ITEM_ROW	equ	14			; the options' lines, ITEM_PITCH rows apart
ITEM_PITCH	equ	3
OPTION_ITEMS	equ	3
ITEM_BACK	equ	2
SCORE_COLUMN	equ	8
SCORE_ROW	equ	12			; the best scores' lines, SCORE_PITCH rows apart
SCORE_PITCH	equ	2

	section	code,code

;--
; TitleShow
; Show the title. No game is on: no fighter, no stage.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
TitleShow:
	move.b	#MODE_TITLE,Mode(a5)
	clr.b	MenuItem(a5)
	clr.w	MenuTimer(a5)
	move.b	#PS_ABSENT,PlayerState(a5)
	clr.b	InPlay(a5)
	clr.b	FlowText(a5)
	move.b	#FL_PLAY,FlowState(a5)
	bsr	HideAll
	lea	NameText(pc),a0
	moveq	#TITLE_COLUMN,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	; falls through

;--
; TitleLines
; Show the title's two lines, the one the stick is on in yellow.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
TitleLines:
	lea	StartText(pc),a0
	moveq	#START_COLUMN,d1
	moveq	#START_ROW,d2
	moveq	#0,d0
	bsr	ItemColour
	moveq	#1,d0
	bsr	TextShow
	lea	OptionsText(pc),a0
	moveq	#OPTIONS_COLUMN,d1
	moveq	#OPTIONS_ROW,d2
	moveq	#1,d0
	bsr	ItemColour
	moveq	#2,d0
	bra	TextShow

;--
; ItemColour
; The colour of a line the stick can be on.
; In:       d0.w = which line it is, a5 = state
; Out:      d3.w = yellow if the stick is on it, else cyan
; Clobbers: -
ItemColour:
	moveq	#TEXT_CYAN,d3
	cmp.b	MenuItem(a5),d0
	bne	.Other
	moveq	#TEXT_YELLOW,d3
.Other	rts

;--
; HideAll
; Take every line of text off.
; In:       a5 = state
; Out:      -
; Clobbers: d0, a0
HideAll:
LINE	set	0
	rept	TEXT_LINES
	moveq	#LINE,d0
	bsr	TextHide
LINE	set	LINE+1
	endr
	rts

;--
; ReadPad
; The stick and the button: what has been pressed since last frame.
; In:       a5 = state, a6 = CUSTOM
; Out:      d0.b = PADB_ bits, set for what is down now and was not
; Clobbers: d1-d2
ReadPad:
	move.w	joy1dat(a6),d1
	moveq	#0,d0
	btst	#JOYB_RIGHT,d1
	beq	.NotRight
	bset	#PADB_RIGHT,d0
.NotRight
	btst	#JOYB_LEFT,d1
	beq	.NotLeft
	bset	#PADB_LEFT,d0
.NotLeft
	move.w	d1,d2
	lsr.w	#1,d2
	eor.w	d1,d2
	btst	#JOYB_DOWN,d2
	beq	.NotDown
	bset	#PADB_DOWN,d0
.NotDown
	btst	#JOYB_UP,d2
	beq	.NotUp
	bset	#PADB_UP,d0
.NotUp	btst	#CIAAB_FIRE1,CIAA_PRA
	bne	.NotFire
	bset	#PADB_FIRE,d0
.NotFire
	move.b	PadWas(a5),d1
	move.b	d0,PadWas(a5)
	not.b	d1
	and.b	d1,d0
	rts

;--
; TitleTick
; Once a displayed frame while no game is on: the stick and the button work the title,
; the options, or the best scores.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
TitleTick:
	bsr	ReadPad
	move.b	d0,d7				; what was pressed
	addq.w	#1,MenuTimer(a5)
	tst.b	d7
	beq	.Quiet
	clr.w	MenuTimer(a5)
.Quiet	move.b	Mode(a5),d0
	cmp.b	#MODE_OPTIONS,d0
	beq	Options
	cmp.b	#MODE_SCORES,d0
	beq	.Scores
	; the title: up or down goes to the other line, the button takes the one it is on
	moveq	#PAD_UP_DOWN,d0
	and.b	d7,d0
	beq	.Still
	bchg	#0,MenuItem(a5)
	bra	TitleLines
.Still	btst	#PADB_FIRE,d7
	beq	.Idle
	tst.b	MenuItem(a5)
	bne	OptionsShow
	clr.b	Mode(a5)			; MODE_GAME
	bsr	HideAll
	bra	GameStart
.Idle	cmp.w	#TITLE_FRAMES,MenuTimer(a5)
	bcc	ScoresShow
	rts
	; the best scores: back to the title at a touch, or after a while
.Scores	tst.b	d7
	bne	TitleShow
	cmp.w	#SCORES_FRAMES,MenuTimer(a5)
	bcc	TitleShow
	rts

;--
; OptionsShow
; Show the options.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d6, a0-a3
OptionsShow:
	move.b	#MODE_OPTIONS,Mode(a5)
	clr.b	MenuItem(a5)
	bsr	HideAll
	lea	OptionsText(pc),a0
	moveq	#OPTIONS_COLUMN,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	; falls through

;--
; OptionLines
; Show the options' lines with their settings, the one the stick is on in yellow.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d6, a0-a3
OptionLines:
	; FIGHTERS and how many: one more than are in reserve
	lea	FightersText(pc),a1
	bsr	Label
	moveq	#'1',d0
	add.b	OptLives(a5),d0
	move.b	d0,(a0)+
	clr.b	(a0)
	moveq	#0,d6
	bsr	OptionLine
	; DIFFICULTY and its name
	lea	DifficultyText(pc),a1
	bsr	Label
	moveq	#0,d0
	move.b	OptRank(a5),d0
	add.w	d0,d0
	lea	RankNames(pc),a1
	add.w	(a1,d0.w),a1
.Name	move.b	(a1)+,(a0)+
	bne	.Name
	moveq	#1,d6
	bsr	OptionLine
	lea	BackText(pc),a1
	bsr	Label
	clr.b	(a0)
	moveq	#ITEM_BACK,d6
	; falls through

;--
; OptionLine
; Show one of the options' lines from TextBuf.
; In:       d6.w = which, 0 to OPTION_ITEMS-1, a5 = state
; Out:      -
; Clobbers: d0-d5, a0-a3
OptionLine:
	lea	TextBuf(a5),a0
	moveq	#ITEM_COLUMN,d1
	move.w	d6,d2
	mulu.w	#ITEM_PITCH,d2
	add.w	#ITEM_ROW,d2
	move.w	d6,d0
	bsr	ItemColour
	move.w	d6,d0
	addq.w	#1,d0				; line 0 is the heading
	bra	TextShow

;--
; Label
; Start a line in TextBuf with a text.
; In:       a1 = the text, 0 ends, a5 = state
; Out:      a0 = where the line goes on
; Clobbers: a1
Label:	lea	TextBuf(a5),a0
.Copy	move.b	(a1)+,(a0)+
	bne	.Copy
	subq.l	#1,a0
	rts

;--
; Options
; A frame of the options: the stick moves between the lines and changes the one it is on.
; In:       d7.b = what was pressed (PADB_ bits), a5 = state
; Out:      -
; Clobbers: d0-d6, a0-a3
Options:
	tst.b	d7
	beq	.Done
	moveq	#0,d0
	move.b	MenuItem(a5),d0
	btst	#PADB_UP,d7
	beq	.NotUp
	subq.w	#1,d0
	bcc	.Moved
	moveq	#OPTION_ITEMS-1,d0
.Moved	move.b	d0,MenuItem(a5)
	bra	OptionLines
.NotUp	btst	#PADB_DOWN,d7
	beq	.Change
	addq.w	#1,d0
	cmp.w	#OPTION_ITEMS,d0
	bne	.Moved
	moveq	#0,d0
	bra	.Moved
	; left, right or the button on a line
.Change	subq.w	#1,d0
	beq	.Rank
	bcc	.Back
	; three fighters or six
	moveq	#RESERVE,d0
	cmp.b	OptLives(a5),d0
	bne	.Lives
	moveq	#RESERVE_MORE,d0
.Lives	move.b	d0,OptLives(a5)
	bra	OptionLines
	; the difficulty: left one easier, right or the button one harder, round and round
.Rank	moveq	#1,d0
	btst	#PADB_LEFT,d7
	beq	.Harder
	moveq	#-1,d0
.Harder	add.b	OptRank(a5),d0
	and.w	#RANKS-1,d0
	move.b	d0,OptRank(a5)
	lea	RankSwitch(pc),a0
	move.b	(a0,d0.w),Rank(a5)
	bra	OptionLines
.Back	btst	#PADB_FIRE,d7
	bne	TitleShow
.Done	rts

;--
; ScoresShow
; Show the best scores.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a3
ScoresShow:
	move.b	#MODE_SCORES,Mode(a5)
	clr.w	MenuTimer(a5)
	bsr	HideAll
	lea	ScoresText(pc),a0
	moveq	#SCORE_COLUMN,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	moveq	#0,d6				; which score
.Score	move.w	d6,d0
	lsl.w	#2,d0
	lea	Places(pc),a1
	add.w	d0,a1
	bsr	Label
	move.b	#' ',(a0)+
	move.b	#' ',(a0)+
	; six digits, two to a byte in the low three bytes; no zeros before the first that counts
	lea	Scores(a5),a1
	move.w	d6,d0
	lsl.w	#2,d0
	move.l	(a1,d0.w),d1
	lsl.l	#8,d1
	moveq	#SCORE_DIGITS-1,d2
	moveq	#' ',d7			; what a zero shows as, so far
.Digit	rol.l	#4,d1
	moveq	#15,d0
	and.w	d1,d0
	bne	.Counts
	tst.w	d2
	bne	.Zero				; but the last one always shows
.Counts	moveq	#'0',d7
.Zero	add.b	d7,d0
	cmp.b	#' ',d7
	bne	.Put
	moveq	#' ',d0
.Put	move.b	d0,(a0)+
	dbf	d2,.Digit
	clr.b	(a0)
	lea	TextBuf(a5),a0
	moveq	#SCORE_COLUMN,d1
	move.w	d6,d2
	mulu.w	#SCORE_PITCH,d2
	add.w	#SCORE_ROW,d2
	moveq	#TEXT_CYAN,d3
	tst.w	d6
	bne	.Line
	moveq	#TEXT_YELLOW,d3			; the best of them
.Line	move.w	d6,d0
	addq.w	#1,d0
	bsr	TextShow
	addq.w	#1,d6
	cmp.w	#SCORES,d6
	bne	.Score
	rts

;--
; ScoresInit
; At the start: the best scores are the arcade's 20000 each, and that is the high score.
; In:       a5 = state
; Out:      -
; Clobbers: d0, a0
ScoresInit:
	lea	Scores(a5),a0
	moveq	#SCORES-1,d0
.Score	move.l	#FIRST_SCORE,(a0)+
	dbf	d0,.Score
	move.l	#FIRST_SCORE,HighScore(a5)
	moveq	#-1,d0				; and no score brings an extra fighter before a game sets one
	move.l	d0,NextBonus(a5)
	rts

;--
; ScoresInsert
; A game is over: its score takes its place among the best, if it has one.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d2, a0
ScoresInsert:
	move.l	Score(a5),d0
	lea	Scores(a5),a0
	moveq	#SCORES-1,d1
.Place	cmp.l	(a0),d0
	bhi	.Here
	addq.l	#4,a0
	dbf	d1,.Place
	rts
	; the ones below move down a place, the last one out
.Here	move.l	(a0),d2
	move.l	d0,(a0)+
	move.l	d2,d0
	dbf	d1,.Here
	rts

NameText:
	dc.b	"AMIGALAGA",0
StartText:
	dc.b	"START GAME",0
OptionsText:
	dc.b	"OPTIONS",0
FightersText:
	dc.b	"FIGHTERS    ",0
DifficultyText:
	dc.b	"DIFFICULTY  ",0
BackText:
	dc.b	"BACK",0
ScoresText:
	dc.b	"BEST SCORES",0
; each of the best scores' lines starts with its place: 4 bytes each, with the 0
Places:	dc.b	"1ST",0,"2ND",0,"3RD",0,"4TH",0,"5TH",0
	even
; the difficulty's names, and the arcade's switch value for each
RankNames:
	dc.w	.Easy-RankNames,.Medium-RankNames,.Hard-RankNames,.Hardest-RankNames
.Easy	dc.b	"EASY",0
.Medium	dc.b	"MEDIUM",0
.Hard	dc.b	"HARD",0
.Hardest
	dc.b	"HARDEST",0
RankSwitch:
	dc.b	3,0,1,2
	even
