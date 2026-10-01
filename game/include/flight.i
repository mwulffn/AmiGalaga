; Flight: an enemy flying a script. See flight.s.

FLIGHT_SLOTS	equ	12		; as many as the arcade flies at once

; An enemy is known by its object number, as in the arcade: even numbers,
; $08-$2e the 20 bees, $30-$36 the 4 bosses, $38-$3e enemies that only fly
; through, $40-$5e the 16 butterflies, $00-$06 captured fighters.
OBJECTS		equ	$80
STAGE_WAVES	equ	5			; a stage's enemies arrive in 5 waves of 8
STAT_LATE	equ	16			; test builds: how many late frames the report lists
; test builds: places in a frame's work where the profile notes the time (see MARK)
PROF_START	equ	0			; the frame's work begins
PROF_PANEL	equ	1			; sprites and panel done
PROF_LOGIC	equ	2			; the arcade frames' logic done
PROF_MOVED	equ	3			; flights moved
PROF_SHOTS	equ	4			; shots, bombs and hits done
PROF_STRIPS	equ	5			; strips rebuilt
PROF_ERASED	equ	6			; flyers erased
PROF_FORMATION	equ	7			; formation drawn
PROF_BEAM	equ	8			; beam drawn
PROF_FLIGHTS	equ	9			; flights drawn
PROF_BLASTS	equ	10			; blasts drawn
PROF_BOMBS	equ	11			; bombs drawn
PROF_TEXT	equ	12			; text drawn
PROF_MARKS	equ	13
WAVE_PAIRS	equ	6			; a wave's eight and up to four that only fly through, in pairs
WAVE_BYTES	equ	STAGE_WAVES*(1+4*WAVE_PAIRS)+1	; a start mark and the (control, object) pairs each, an end mark
WAVE_PLACES	equ	16			; places for a wave being put together: 8 for each half

; Time is counted in fifths of an arcade frame. A displayed frame uses up
; FIFTHS of them: 6 on a 50 Hz display, which keeps the arcade's speed;
; 5 reproduces the arcade exactly and is the build that is checked against it.
FIFTHS		equ	6-EXACT_TIMING
FRAME_FIFTHS	equ	5		; fifths in one arcade frame

; dives
STAGE_PARMS	equ	10
DIVE_KINDS	equ	3
DIVE_QUEUE	equ	4
	rsreset
dq_obj		rs.b	1			; the object, bit 7 set to fly mirrored; QUEUE_EMPTY if none
dq_pad		rs.b	1
dq_script	rs.w	1
dq_SIZEOF	rs.b	0
QUEUE_EMPTY	equ	$ff

; what FlightStep returns
FLIGHT_FLYING	equ	0
FLIGHT_HOME	equ	1		; reached its place in the formation
FLIGHT_GONE	equ	2		; its script ended

; a STAGE_TEST build logs these two, launches, a checksum of the formation's table each frame,
; a boss's first hit, every enemy destroyed and the score's last four digits after it,
; every bomb dropped (with its rate), every fighter lost (with the reserve) and every
; stage set up (with its number)
STAGE_LAUNCHED	equ	0
STAGE_FORMATION	equ	3
STAGE_KILLED	equ	4
STAGE_BOSS_HIT	equ	5
STAGE_SCORE_HI	equ	6
STAGE_SCORE_LO	equ	7
STAGE_FIGHTER_LOST equ	8
STAGE_BOMB	equ	9
STAGE_BEGUN	equ	10
STAGE_LOG_BYTES	equ	4*12288

; fl_flags bits
FLB_ACTIVE	equ	0
FLB_PAUSE	equ	1		; standing still for one arcade frame
FLB_DIVING	equ	2		; watching for its dive depth
FLB_HOMING	equ	3		; heading for its place in the formation
FLB_LANDED	equ	4		; home, and drawn there until its row's strip is next rebuilt
FLB_MIRROR	equ	7		; flies the script mirrored

; Positions are in the arcade's own space, 1/128 pixel: x from the left,
; y from the bottom. On the 224 x 288 arcade screen the sprite's left edge
; is x/128 - 17 and its top edge is 312 - y/128; a homing enemy is drawn
; fl_xo to the right and fl_yo lower.
	rsreset
fl_y		rs.w	1
fl_x		rs.w	1
fl_head		rs.l	1		; heading: 2^32 is a full turn, 0 is right, a quarter is up
fl_turn		rs.l	1		; heading added per displayed frame within a step
fl_dist		rs.w	2		; distance per displayed frame: even frames, odd frames
fl_script	rs.w	1		; next token, as an offset into MotionScripts
fl_left		rs.w	1		; fifths left in the current step
fl_rate		rs.b	1		; the step's turn rate, mirrored if the flight is
fl_lo		rs.b	1		; the step's two speeds: odd frames,
fl_hi		rs.b	1		;   even frames
fl_flags	rs.b	1
fl_ty		rs.b	1		; target: home (y, x in two-pixel units), or dive depth
fl_tx		rs.b	1
fl_yo		rs.b	1		; while homing: the formation's offset when it turned for home
fl_xo		rs.b	1
fl_obj		rs.b	1		; which enemy this is: selects its place in the formation
fl_wait		rs.b	1		; arcade frames to its next chance to drop a bomb
fl_chances	rs.b	1		; its chances: a bit each, low bit first; set = it drops one
fl_pad		rs.b	1
fl_SIZEOF	rs.b	0

; the fighter's shots: where each is, as the arcade's sprite hardware counts
SHOTS		equ	2			; shots in flight at once, as the arcade has it
MAX_SHOTS	equ	4			;   and the most the options allow
	rsreset
sh_x		rs.w	1			; 0: not in flight
sh_y		rs.w	1
sh_wide		rs.b	1			; nonzero: fired by two fighters, a second bullet beside it
sh_pad		rs.b	1
sh_SIZEOF	rs.b	0

; an enemy blowing up, and the score that may appear where it was
BLASTS		equ	8
	rsreset
bl_x		rs.w	1			; in buffer pixels and rows, of the 16x16 it filled
bl_y		rs.w	1
bl_image	rs.l	1			; what it looked like, shown until the blast starts
bl_live		rs.b	1
bl_obj		rs.b	1			; which enemy: decides on which frames it steps
bl_step		rs.b	1
bl_popup	rs.b	1			; which score follows: 0 = 400, 1 = 800, 2 = 1600, 3 = 1000, 4 = 1500, 5 = 2000, 6 = 3000; negative: none
bl_SIZEOF	rs.b	0
POPUP_NONE	equ	-1
POPUP_WIDE	equ	5			; from here on a score is two images side by side

; an enemy's bomb, placed as the arcade's sprite hardware counts
	ifnd	BOMBS
BOMBS		equ	8			; as many as the arcade
	endc
	rsreset
bm_x		rs.w	1			; 0: not falling
bm_y		rs.w	1
bm_rate		rs.b	1			; sideways: 32nds of a pixel per arcade frame, bit 7 = leftwards
bm_carry	rs.b	1			; the 32nds left over
bm_SIZEOF	rs.b	0
ENTRY_WAIT	equ	8			; fl_wait for an enemy arriving from the top,
SIDE_WAIT	equ	$44			;   from the sides,
DIVE_WAIT	equ	$1e			;   and diving

; what the fighter is doing (PlayerState)
PS_PLAYING	equ	0
PS_BLOWN	equ	1			; exploding, then gone, until GameTimer runs out
PS_RETURNING	equ	2			; waiting for the divers to go home
PS_READY	equ	3			; back, and can move, but not fire or be hit, until GameTimer runs out
PS_OVER		equ	4			; no fighters left: until GameTimer runs out, then a new game
PS_ABSENT	equ	5			; not there yet: a new game's opening
PS_TAKEN	equ	6			; in the tractor beam, or carried off
PS_RESULTS	equ	7			;   the game is over: its results show
RESERVE		equ	2			; fighters in reserve at the start: three in all
RESERVE_MORE	equ	5			;   or, by the options, six
; what is on: Mode
MODE_GAME	equ	0			; a game
MODE_TITLE	equ	1			; the title, with START GAME and OPTIONS
MODE_OPTIONS	equ	2			; the options
MODE_SCORES	equ	3			; the best scores
MODE_ENTRY	equ	4			; a game's score is one of them: its initials are entered
NAME_BYTES	equ	4			; a best score's three initials and a 0
SCORES		equ	5			; how many of those are kept
RANKS		equ	4			; settings of the arcade's difficulty switch

; a line of text in the playfield (text.s)
TEXT_LINES	equ	6
TEXT_CELLS	equ	12			; flyers a line: two letters each
	rsreset
ts_cells	rs.w	1			; flyers showing; 0: the line is not shown
ts_x		rs.w	1			; in buffer pixels and rows
ts_y		rs.w	1
ts_SIZEOF	rs.b	0
; the palette entries text is written in
TEXT_CYAN	equ	5
TEXT_RED	equ	2
TEXT_YELLOW	equ	3
TEXT_WHITE	equ	1

; where the game is between stages (FlowState)
FL_PLAY		equ	0			; a stage is running
FL_INTRO	equ	1			; a new game: PLAYER 1 and the start theme
FL_CLEARED	equ	2			; the stage is cleared: a pause
FL_RESULTS	equ	3			; a challenging stage's results
FL_SPLASH	equ	4			; STAGE n and its badges
FL_ENTER	equ	5			; the first stage: the fighter comes on
BADGE_PLACES	equ	10			; badge columns the panel has room for
BADGEB_FIRST	equ	7			; BadgeList: the first column of a badge

; the captured fighter (CaptiveState)
CS_NONE		equ	0
CS_CARRIED	equ	1			; with the boss that caught it, on the way home
CS_PLACED	equ	2			; in the formation, above its boss
CS_FLYING	equ	3			; in a flight: diving with its boss, or alone
CS_RESCUED	equ	4			;   free again: spinning, then coming down to the fighter
