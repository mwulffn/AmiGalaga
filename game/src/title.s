; Title: what shows when no game is on, the options, and the best scores.
;
; The arcade's coin slot, its start buttons and its second player are gone.
; Instead:
;   The title: the game's name, START GAME, OPTIONS and QUIT. The stick moves
;     between them, the button takes one. QUIT ends the program and gives the
;     machine back to the system (startup.s saves the best scores on the way).
;     Left alone for a while the title gives way to
;   the best scores: five, each with three initials. They give way to the
;     title again after a while or at a touch.
;   The options: how many fighters a game starts with (three, as the arcade
;     comes, or six) and the arcade's difficulty switch (its four ranks, which
;     pick the stage tables: see stage.s and dives.s). The stick moves between
;     the lines and changes the one it is on; the button on BACK goes back.
;   Entering initials: a game that ends with one of the five best scores comes
;     here instead of to the title. The score is in the list already, as AAA,
;     in yellow; the stick left and right changes the letter that blinks, the
;     button goes on to the next, and after the third (or 20 seconds without a
;     touch) the list stays for a while as the best scores. The arcade's tunes
;     play: its own for the best score of all, a loop for the others.
; A game that ends comes back here by way of GameInit.
;
;   The attract mode: after the best scores a game plays by itself, silently,
;     with one fighter that goes from side to side and fires (the test builds'
;     player). It lasts until that fighter is lost, 45 seconds at most, and
;     the button ends it at once; then the title again. Its score counts for
;     nothing. This is not the arcade's own demonstration, which is a scripted
;     scene; it is the game itself.
;
; While the title, options or scores show, the game runs with no stage and no
; fighter; the text is the game's own (text.s).

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	TitleShow
	xdef	TitleTick
	xdef	EntryShow
	xdef	DemoTick
	xdef	ScoresInit
	xdef	ScoresInsert
	xref	GameStart
	xref	CaptureInit
	xref	SoundPause
	xref	TextShow
	xref	TextHide

; the stick and the button, as ReadPad gives them
PADB_UP		equ	0
PADB_DOWN	equ	1
PADB_LEFT	equ	2
PADB_RIGHT	equ	3
PADB_FIRE	equ	4
PAD_SIDES	equ	1<<PADB_LEFT|1<<PADB_RIGHT
JOYB_DOWN	equ	0			; joy1dat: this bit and the next differ when the stick is down,
JOYB_UP		equ	8			;   this one and the next when it is up
TITLE_FRAMES	equ	8*50			; the title gives way to the best scores after this long,
SCORES_FRAMES	equ	8*50			;   and they to the title
ENTRY_FRAMES	equ	20*50			; initials left alone this long are taken as they are
DEMO_FRAMES	equ	45*50			; the attract mode's game lasts this long at most
DEMO_ROW	equ	1
DEMO_COLUMN	equ	6
DEMO_LINE	equ	5			; the line of text the attract mode's notice is on
REPEAT_DELAY	equ	20			; frames the stick is held before the letter runs on,
REPEAT_EVERY	equ	6			;   and frames between letters then
BLINK_FRAMES	equ	16			; the letter being chosen shows and hides this often
FIRST_SCORE	equ	$00020000		; every one of the best scores at the start, as the arcade's
FIRST_NAME	equ	'...'<<8		; and whose they are then
NEW_NAME	equ	'AAA'<<8		; a new score's initials before they are chosen
SCORE_DIGITS	equ	6
NAME_AT		equ	3+2+SCORE_DIGITS+2	; where the initials are in a best score's line
; where things go, in characters of the playfield
HEAD_ROW	equ	8
TITLE_COLUMN	equ	9
TITLE_ITEMS	equ	3
ITEM_QUIT	equ	2
MENU_ROW	equ	16			; the title's lines, ITEM_PITCH rows apart
ITEM_COLUMN	equ	5
ITEM_PITCH	equ	3
OPTIONS_COLUMN	equ	10
OPTION_ITEMS	equ	4
ITEM_SHOTS	equ	2
ITEM_BACK	equ	3
ITEM_ROW_TOP	equ	12			; the options' lines, ITEM_PITCH rows apart
SCORE_COLUMN	equ	6
SCORE_ROW	equ	12			; the best scores' lines, SCORE_PITCH rows apart
SCORE_PITCH	equ	2
ENTER_COLUMN	equ	4

	section	code,code

;--
; TitleShow
; Show the title. No game is on: no fighter, no stage.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d6, a0-a3
TitleShow:
	move.b	#MODE_TITLE,Mode(a5)
	clr.b	MenuItem(a5)
	bsr	NoGame
	lea	NameText(pc),a0
	moveq	#TITLE_COLUMN,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	; falls through

;--
; TitleLines
; Show the title's lines, the one the stick is on in yellow.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d6, a0-a3
TitleLines:
	moveq	#0,d6
.Line	move.w	d6,d0
	lsl.w	#2,d0
	lea	TitleItems(pc),a1
	add.w	d0,a1
	lea	TitleItems(pc),a0
	add.w	(a1)+,a0			; its text
	move.w	(a1),d1				; its column
	move.w	d6,d2
	mulu.w	#ITEM_PITCH,d2
	add.w	#MENU_ROW,d2
	move.w	d6,d0
	bsr	ItemColour
	move.w	d6,d0
	addq.w	#1,d0				; line 0 is the name
	bsr	TextShow
	addq.w	#1,d6
	cmp.w	#TITLE_ITEMS,d6
	bne	.Line
	rts

;--
; NoGame
; No game is on: no fighter, no stage's messages, no text, the idle clock at nought.
; In:       a5 = state
; Out:      -
; Clobbers: d0, a0
NoGame:	clr.w	MenuTimer(a5)
	move.b	#PS_ABSENT,PlayerState(a5)
	clr.b	InPlay(a5)
	clr.b	FlowText(a5)
	move.b	#FL_PLAY,FlowState(a5)
	; falls through

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
; ReadPad
; The stick and the button: what has been pressed since last frame. PadWas has what is
; down now.
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
; MenuMove
; Move the stick's line up or down, round and round.
; In:       d7.b = what was pressed (PADB_ bits), d1.w = how many lines there are, a5 = state
; Out:      Z = it did not move
; Clobbers: d0
MenuMove:
	moveq	#0,d0
	move.b	MenuItem(a5),d0
	btst	#PADB_UP,d7
	beq	.NotUp
	subq.w	#1,d0
	bcc	.Moved
	move.w	d1,d0
	subq.w	#1,d0
	bra	.Moved
.NotUp	btst	#PADB_DOWN,d7
	beq	.Still
	addq.w	#1,d0
	cmp.w	d1,d0
	bne	.Moved
	moveq	#0,d0
.Moved	move.b	d0,MenuItem(a5)
	moveq	#1,d0
	rts
.Still	moveq	#0,d0
	rts

;--
; TitleTick
; Once a displayed frame while no game is on: the stick and the button work the title,
; the options, the best scores or the initials.
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
	cmp.b	#MODE_ENTRY,d0
	beq	Initials
	cmp.b	#MODE_SCORES,d0
	beq	.Scores
	if	SAVE_TEST
	; no joystick needed: a score, its initials, and out
	cmp.w	#3*50,MenuTimer(a5)
	bne	.Menu
	move.l	#$00054320,Score(a5)
	bsr	ScoresInsert
	tst.w	d0
	bmi	.Quit
	lsl.w	#2,d0
	lea	Names(a5),a0
	move.l	#'TST'<<8,(a0,d0.w)
	st	ScoresDirty(a5)
	bra	.Quit
.Menu
	endc
	; the title: up and down move between the lines, the button takes the one it is on
	moveq	#TITLE_ITEMS,d1
	bsr	MenuMove
	bne	TitleLines
	btst	#PADB_FIRE,d7
	beq	.Idle
	move.b	MenuItem(a5),d0
	beq	.Start
	subq.b	#ITEM_QUIT,d0
	bne	OptionsShow
.Quit	st	QuitWanted(a5)
	rts
.Start	clr.b	Mode(a5)			; MODE_GAME
	bsr	HideAll
	bra	GameStart
.Idle	cmp.w	#TITLE_FRAMES,MenuTimer(a5)
	bcc	ScoresShow
	rts
	; the best scores: back to the title at a touch; left alone, the attract mode
.Scores	tst.b	d7
	bne	TitleShow
	cmp.w	#SCORES_FRAMES,MenuTimer(a5)
	bcc	DemoStart
	rts

;--
; DemoStart
; The attract mode: a game that plays by itself, silently, with one fighter.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d5, a0-a3
DemoStart:
	move.l	Score(a5),DemoScore(a5)
	clr.b	Mode(a5)			; MODE_GAME
	st	Demo(a5)
	clr.w	DemoTimer(a5)
	bsr	GameStart
	bsr	SoundPause			; the start theme it asked for is never heard
	clr.b	Lives(a5)
	st	PadRight(a5)
	clr.b	PadLeft(a5)
	lea	DemoText(pc),a0
	moveq	#DEMO_COLUMN,d1
	moveq	#DEMO_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#DEMO_LINE,d0
	bra	TextShow

;--
; DemoTick
; A frame of the attract mode's game: it ends at the button, when its fighter is lost, or
; after DEMO_FRAMES. GameInit then puts everything back and shows the title.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d2, a0
DemoTick:
	bsr	ReadPad
	btst	#PADB_FIRE,d0
	bne	.End
	addq.w	#1,DemoTimer(a5)
	cmp.w	#DEMO_FRAMES,DemoTimer(a5)
	bcc	.End
	cmp.b	#PS_OVER,PlayerState(a5)
	bne	.Done
.End	bsr	CaptureInit			; no captured fighter, and no beam left on the screen
	move.b	#SCREENS,BeamWipe(a5)
	moveq	#DEMO_LINE,d0
	bsr	TextHide
	st	NewGame(a5)
.Done	rts

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
	; SHOTS and how many can be in flight
	lea	ShotsText(pc),a1
	bsr	Label
	moveq	#'0',d0
	add.b	OptShots(a5),d0
	move.b	d0,(a0)+
	clr.b	(a0)
	moveq	#ITEM_SHOTS,d6
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
	add.w	#ITEM_ROW_TOP,d2
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
	moveq	#OPTION_ITEMS,d1
	bsr	MenuMove
	bne	OptionLines
	; left, right or the button on a line
	moveq	#0,d0
	move.b	MenuItem(a5),d0
	subq.w	#1,d0
	beq	.Rank
	bcs	.Fighters
	subq.w	#ITEM_SHOTS-1,d0
	bne	.Back
	; shots in flight at once: the arcade's two, up to MAX_SHOTS, round and round
	moveq	#1,d0
	btst	#PADB_LEFT,d7
	beq	.More
	moveq	#-1,d0
.More	add.b	OptShots(a5),d0
	cmp.b	#SHOTS,d0
	bcc	.Least
	moveq	#MAX_SHOTS,d0
.Least	cmp.b	#MAX_SHOTS,d0
	bls	.Most
	moveq	#SHOTS,d0
.Most	move.b	d0,OptShots(a5)
	bra	OptionLines
	; three fighters or six
.Fighters
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
	moveq	#SCORE_COLUMN+2,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	; falls through

;--
; ScoreLines
; Show every one of the best scores.
; In:       a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a3
ScoreLines:
	moveq	#0,d6
.Score	bsr	ScoreLine
	addq.w	#1,d6
	cmp.w	#SCORES,d6
	bne	.Score
	rts

;--
; ScoreLine
; Show one of the best scores: its place, the score, its initials. The best is yellow; or,
; while initials are entered, the one they are for, whose letter being chosen blinks.
; In:       d6.w = which, 0 the best, a5 = state
; Out:      -
; Clobbers: d0-d5, d7, a0-a3
ScoreLine:
	move.w	d6,d0
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
	moveq	#' ',d7				; what a zero shows as, so far
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
	move.b	#' ',(a0)+
	move.b	#' ',(a0)+
	lea	Names(a5),a1
	move.w	d6,d0
	lsl.w	#2,d0
	add.w	d0,a1
	move.b	(a1)+,(a0)+
	move.b	(a1)+,(a0)+
	move.b	(a1),(a0)+
	clr.b	(a0)
	moveq	#TEXT_CYAN,d3
	cmp.b	#MODE_ENTRY,Mode(a5)
	beq	.Entry
	tst.w	d6
	bne	.Show
	moveq	#TEXT_YELLOW,d3			; the best of them
	bra	.Show
.Entry	cmp.b	EntryPlace(a5),d6
	bne	.Show
	moveq	#TEXT_YELLOW,d3
	; the letter being chosen hides every other BLINK_FRAMES; a space shows as a dash then
	moveq	#BLINK_FRAMES,d0
	and.w	FrameCount(a5),d0
	beq	.Show
	lea	TextBuf+NAME_AT(a5),a0
	moveq	#0,d0
	move.b	EntryAt(a5),d0
	add.w	d0,a0
	moveq	#' ',d0
	cmp.b	(a0),d0
	bne	.Hide
	moveq	#'-',d0
.Hide	move.b	d0,(a0)
.Show	lea	TextBuf(a5),a0
	moveq	#SCORE_COLUMN,d1
	move.w	d6,d2
	mulu.w	#SCORE_PITCH,d2
	add.w	#SCORE_ROW,d2
	move.w	d6,d0
	addq.w	#1,d0
	bra	TextShow

;--
; EntryShow
; A game's score is among the best: show the list with it in, and ask for its initials.
; In:       d0.w = its place, 0 the best, a5 = state
; Out:      -
; Clobbers: d0-d7, a0-a3
EntryShow:
	move.b	#MODE_ENTRY,Mode(a5)
	move.b	d0,EntryPlace(a5)
	clr.b	EntryAt(a5)
	clr.b	PadHold(a5)
	st	ScoresDirty(a5)
	bsr	NoGame
	; the arcade's tunes: its own for the best score of all, a loop for the others
	if	SOUND_TEST=0
	tst.b	EntryPlace(a5)
	bne	.Loop
	move.b	#1,Sound+SND_NAME_A(a5)
	bra	.Tune
.Loop	move.b	#1,Sound+SND_NAME_LOOP(a5)
.Tune
	endc
	lea	EnterText(pc),a0
	moveq	#ENTER_COLUMN,d1
	moveq	#HEAD_ROW,d2
	moveq	#TEXT_WHITE,d3
	moveq	#0,d0
	bsr	TextShow
	bra	ScoreLines

;--
; Initials
; A frame of entering initials: left and right change the letter, the button takes it.
; In:       d7.b = what was pressed (PADB_ bits), a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
Initials:
	; the stick held to one side runs on through the letters
	moveq	#PAD_SIDES,d0
	and.b	PadWas(a5),d0
	beq	.Free
	addq.b	#1,PadHold(a5)
	cmp.b	#REPEAT_DELAY,PadHold(a5)
	bcs	.Keys
	move.b	#REPEAT_DELAY-REPEAT_EVERY,PadHold(a5)
	or.b	d0,d7
	bra	.Keys
.Free	clr.b	PadHold(a5)
.Keys	moveq	#0,d6
	move.b	EntryPlace(a5),d6
	lea	Names(a5),a1
	move.w	d6,d0
	lsl.w	#2,d0
	add.w	d0,a1
	moveq	#0,d0
	move.b	EntryAt(a5),d0
	add.w	d0,a1				; the letter being chosen
	moveq	#PAD_SIDES,d0
	and.b	d7,d0
	beq	.Button
	; where it is among the letters, then one on or one back, round and round
	lea	Letters(pc),a0
	moveq	#0,d0
.Find	move.b	(a0,d0.w),d1
	cmp.b	(a1),d1
	beq	.Found
	addq.w	#1,d0
	cmp.w	#LETTERS,d0
	bne	.Find
	moveq	#0,d0
.Found	btst	#PADB_RIGHT,d7
	beq	.Back
	addq.w	#1,d0
	cmp.w	#LETTERS,d0
	bne	.Set
	moveq	#0,d0
	bra	.Set
.Back	subq.w	#1,d0
	bcc	.Set
	moveq	#LETTERS-1,d0
.Set	move.b	(a0,d0.w),(a1)
	bra	ScoreLine
.Button	btst	#PADB_FIRE,d7
	beq	.Wait
	addq.b	#1,EntryAt(a5)
	cmp.b	#NAME_BYTES-1,EntryAt(a5)
	beq	.Done
	bra	ScoreLine
	; nothing pressed: the blink, and the patience
.Wait	cmp.w	#ENTRY_FRAMES,MenuTimer(a5)
	bcc	.Done
	moveq	#BLINK_FRAMES-1,d0
	and.w	FrameCount(a5),d0
	beq	ScoreLine
	rts
.Done	if	SOUND_TEST=0
	clr.b	Sound+SND_NAME_LOOP(a5)
	endc
	bra	ScoresShow

;--
; ScoresInit
; At the start: unless they were read from disk, the best scores are the arcade's 20000
; each. The best is the high score.
; In:       a5 = state
; Out:      -
; Clobbers: d0, a0-a1
ScoresInit:
	tst.b	ScoresLoaded(a5)
	bne	.High
	lea	Scores(a5),a0
	lea	Names(a5),a1
	moveq	#SCORES-1,d0
.Score	move.l	#FIRST_SCORE,(a0)+
	move.l	#FIRST_NAME,(a1)+
	dbf	d0,.Score
.High	move.l	Scores(a5),HighScore(a5)
	moveq	#-1,d0				; and no score brings an extra fighter before a game sets one
	move.l	d0,NextBonus(a5)
	rts

;--
; ScoresInsert
; A game is over: its score takes its place among the best, if it has one, as AAA.
; In:       a5 = state
; Out:      d0.w = its place, 0 the best, or negative if it has none
; Clobbers: d1-d3, a0
ScoresInsert:
	move.l	Score(a5),d3
	lea	Scores(a5),a0
	moveq	#0,d1
.Place	cmp.l	(a0)+,d3
	bhi	.Here
	addq.w	#1,d1
	cmp.w	#SCORES,d1
	bne	.Place
	moveq	#-1,d0
	rts
	; the ones below move down a place, the last one out
.Here	moveq	#SCORES-1,d2
.Down	cmp.w	d1,d2
	beq	.Put
	move.w	d2,d0
	lsl.w	#2,d0
	lea	Scores(a5),a0
	move.l	-4(a0,d0.w),(a0,d0.w)
	lea	Names(a5),a0
	move.l	-NAME_BYTES(a0,d0.w),(a0,d0.w)
	subq.w	#1,d2
	bra	.Down
.Put	move.w	d1,d0
	lsl.w	#2,d0
	lea	Scores(a5),a0
	move.l	d3,(a0,d0.w)
	lea	Names(a5),a0
	move.l	#NEW_NAME,(a0,d0.w)
	move.w	d1,d0
	rts

NameText:
	dc.b	"AMIGALAGA",0
OptionsText:
	dc.b	"OPTIONS",0
FightersText:
	dc.b	"FIGHTERS    ",0
DifficultyText:
	dc.b	"DIFFICULTY  ",0
BackText:
	dc.b	"BACK",0
ShotsText:
	dc.b	"SHOTS       ",0
DemoText:
	dc.b	"PUSH FIRE TO PLAY",0
ScoresText:
	dc.b	"BEST SCORES",0
EnterText:
	dc.b	"ENTER YOUR INITIALS",0
; the letters initials are made of, in the order the stick goes through them
Letters:
	dc.b	"ABCDEFGHIJKLMNOPQRSTUVWXYZ. "
LETTERS	equ	*-Letters
; each of the best scores' lines starts with its place: 4 bytes each, with the 0
Places:	dc.b	"1ST",0,"2ND",0,"3RD",0,"4TH",0,"5TH",0
	even
; the title's lines: text, column
TitleItems:
	dc.w	.Start-TitleItems,9
	dc.w	.Options-TitleItems,10
	dc.w	.Quit-TitleItems,12
.Start	dc.b	"START GAME",0
.Options
	dc.b	"OPTIONS",0
.Quit	dc.b	"QUIT",0
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
