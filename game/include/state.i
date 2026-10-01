; The game state. A5 holds its address everywhere; fields are used as Name(a5).
; Include config.i, layout.i, flight.i and sound.i first.

	rsreset
FrameCount	rs.w	1		; vertical blanks since start
FrontScreen	rs.l	1		; the screen being shown (a scr_ structure)
BackScreen	rs.l	1		; the screen being drawn
StarFirst	rs.w	1		; star table entry shown on the first line, 0-255
StarSpeed	rs.w	1		; lines the stars scroll per frame
StarTarget	rs.b	1		;   the speed they work up to, in 64ths of a line per arcade frame
StarNow		rs.b	1		;   their speed now
StarCarry	rs.b	1		;   the 64ths left over
StarPad		rs.b	1
StarSteps	rs.w	1		;   lines to scroll, gathered over this frame's arcade frames
StarFade	rs.l	1		; next entry of the fade schedule
ReportPtr	rs.l	1		; test builds: what to write to "results"
ReportLen	rs.l	1
FrameStart	rs.w	1		; test builds: FrameCount when this frame's work began
StatWorst	rs.w	1		; test builds: most raster lines a frame's work took
StatTotal	rs.l	1		;   their sum
StatFrames	rs.w	1		;   and how many frames
StatWorstAt	rs.w	1		;   which frame the worst was
StatOver	rs.w	1		;   how many took more than a frame
StatLate	rs.w	3*STAT_LATE	;   the first of those: frame, lines, and what was on: flights, landed, bombs, blasts (a nibble each)
STAT_SIZE	equ	12+6*STAT_LATE
FormRows	rs.w	2*FORM_ROWS	; formation: per row, x and y of its strip, set when composed
FormPresent	rs.w	FORM_ROWS	;   per row: bit n set if the enemy in column n is there
Score		rs.l	1		; six decimal digits, two to a byte, in the low three bytes
ScoreText	rs.b	8		; scratch for printing it
ShipX		rs.w	1		; the fighter, in playfield pixels
Shots		rs.b	SHOTS*sh_SIZEOF	; its shots
PadLeft		rs.b	1		; player: nonzero while the stick is held left,
PadRight	rs.b	1		;   right
FireWas		rs.b	1		;   nonzero if the button was down last frame
FirePending	rs.b	1		;   nonzero: a press that has not fired its shot yet
MoveFlag	rs.b	1		;   alternates while the stick is held: 1 pixel, then 2
ShotHit		rs.b	1		; shots: nonzero once the shot being tested has hit something
ShotFlying	rs.b	1		;   nonzero if what it destroyed was flying: that scores double
PlayerPad	rs.b	1
PlayerState	rs.b	1		;   what the fighter is doing: a PS_ value
InPlay		rs.b	1		;   nonzero while it can fire and be hit, and the enemy attacks
FighterStep	rs.b	1		;   its explosion: counts down from 15; 0: nothing to see
Lives		rs.b	1		;   fighters in reserve
GameTimer	rs.b	1		;   counts down, one every 32 arcade frames: the pauses around losing a fighter
BombReload	rs.b	1		; bombs: fl_wait after each chance, from the stage's row
EntryBombs	rs.b	1		;   the chances of an enemy that may bomb on its way in
NewGame		rs.b	1		; nonzero: the game is over and the next frame starts a new one
FlowState	rs.b	1		; flow: where the game is between stages, an FL_ value
FlowTimer	rs.b	1		;   counts down, one every 32 arcade frames
FlowStep	rs.b	1		;   how far a challenging stage's results have got
FlowText	rs.b	1		;   which of the fighter's messages shows: 0 none, 1 READY, 2 GAME OVER
FirstStage	rs.b	1		;   nonzero until a game's first stage is running
FlyingHits	rs.b	1		; stage: enemies shot while flying: a challenging stage's "number of hits"
WaveHits	rs.b	1		;   challenging stage: enemies of the wave still to shoot for its bonus
WaveTimer	rs.b	1		; launcher: counts down every 32 arcade frames; spaces a challenging stage's waves
BadgeCount	rs.b	1		; panel: columns of stage badges in BadgeList,
BadgeShown	rs.b	1		;   how many of them are showing yet,
BadgeWait	rs.b	1		;   and arcade frames to the next one
BadgePad	rs.b	1
BadgeList	rs.b	BADGE_PLACES	;   per column: its top tile; bit 7 set on a badge's first column
HighScore	rs.l	1		; as Score
NextBonus	rs.l	1		; the score that brings the next extra fighter
TextLines	rs.b	TEXT_LINES*ts_SIZEOF	; text in the playfield
TextBuf		rs.b	2*TEXT_CELLS+2	; scratch for a line with a number in it
ShipSY		rs.w	1		; player: the fighter's y as the arcade counts; it changes only in the beam
ShipCode	rs.b	1		;   which way it is turned: frame 0-6 (6 upright)
ShipCtrl	rs.b	1		;   and flip, as an enemy's
ShipGone	rs.b	1		;   nonzero: not drawn (the captured fighter is drawn in its place)
FireOff		rs.b	1		; capture: nonzero once the fighter is too far up the beam to get away
BeamColumn	rs.b	1		;   the beam's centre: the sprite x the boss stops at
BeamStep	rs.b	1		;   the beam's progress: the arcade's counter, 1-10 out, $40 held, $41-$4a in, bit 7 shot
BeamWait	rs.b	1		;   arcade frames to its next step
BeamFrames	rs.b	1		;   arcade frames per step
BeamTop		rs.b	1		;   rows of it showing: from this one
BeamBottom	rs.b	1		;   to before this one
BeamWipe	rs.b	1		;   frames the beam's place is still to be cleared after it has gone
Pulling		rs.b	1		;   nonzero while the fighter is being drawn up
Connected	rs.b	1		;   nonzero: the boss has the fighter
ApproachOn	rs.b	1		;   nonzero: a boss is on its way down to capture
BeamOn		rs.b	1		;   nonzero: the beam is out
PullOn		rs.b	1		;   nonzero: the fighter is in the beam
CarryOn		rs.b	1		;   nonzero: the boss is taking the fighter home
CapText		rs.b	1		;   nonzero: FIGHTER CAPTURED is due
CapTimer	rs.b	1		;   counts down every 32 arcade frames while it shows
JoinCount	rs.b	1		;   lines the captured fighter has moved up into its place
StarBack	rs.b	1		; stars: nonzero: they run backwards (the fighter is being pulled up)
CaptiveState	rs.b	1		; captured fighter: a CS_ value
CaptiveObj	rs.b	1		;   its object number: its boss's and 7
CaptiveCode	rs.b	1		;   which way it is turned: frame 0-7
CaptiveCtrl	rs.b	1		;   and flip
CaptiveWhite	rs.b	1		;   nonzero: it is drawn white, rescued
RescueOn	rs.b	1		; rescue: nonzero while a freed fighter spins and comes down
RescueStep	rs.b	1		;   0 just freed, 1 spinning, 2 coming down, 3 down
Docking		rs.b	1		;   nonzero: the fighter makes room, and cannot be steered, fire or be hit
Dual		rs.b	1		; nonzero: two fighters side by side
Bang2Step	rs.b	1		; one of two fighters blowing up: steps left, 0 = none
CaptivePad	rs.b	1
CaptiveX	rs.w	1		;   where it is, as the arcade's sprite hardware counts
CaptiveY	rs.w	1
Bang2X		rs.w	1		;   where it blows up: playfield x
BeamX		rs.w	1		; capture: the beam's left edge in buffer pixels
CaptureSlot	rs.l	1		;   the capturing boss's flight
TicksNow	rs.w	1
TickFrame	rs.w	1		; which arcade frame the shots, bombs and collisions are at		; arcade frames that began in this displayed frame
ScoreStep	rs.l	1		; scratch for adding to the score
Clock		rs.w	1		; fifths of an arcade frame until the next one begins
ArcadeFrame	rs.w	1		; arcade frames so far: what the arcade's own timers count
Stage		rs.w	1		; 1 is the first
StageWait	rs.w	1		; until there is a game: frames since the stage was all in
WaveAt		rs.w	1		; launcher: where it is in WaveTable
WasFlying	rs.w	1		;   flights in the air one arcade frame ago
Flying		rs.w	1		;   how many the arcade's logic takes to be flying: it hears a frame late
FormNext	rs.w	1		; formation: the row whose strip is rebuilt next
FormDrift	rs.w	1		;   how far it has drifted sideways as a whole, in pixels
FormDrifting	rs.b	1		;   nonzero while it drifts; then it breathes
FormLeftwards	rs.b	1		;   nonzero: drifting left
FormCount	rs.b	1		;   breathing: steps out so far; bit 7 set on the way back in
WavesIn		rs.b	1		; launcher: nonzero once every wave is launched and has landed
Alive		rs.b	1		; stage: enemies sent in and not yet destroyed
StageTime	rs.b	1		;   counts down from 120, one every 32 arcade frames
MaxFlying	rs.b	1		; dives: no new one while this many are flying
BombFlags	rs.b	1		;   which of a diver's chances to bomb are taken
Capturing	rs.b	1		;   nonzero: a boss is out to capture, the others take escorts
CaptureBoss	rs.b	1		;   which boss that is
BossToggle	rs.b	1		;   every other boss dive is a capture attempt
Special		rs.b	1		;   the enemy that is about to transform: it does not dive
FormDirty	rs.b	1		; formation: bit n set if row n's strip must be rebuilt this frame
StagePad	rs.b	1
StageParms	rs.b	STAGE_PARMS	; the stage's ten settings, see dives.s
DiveTimers	rs.b	DIVE_KINDS	; dives: per kind (boss, butterfly, bee), 16-frame periods to its next
DiveReload	rs.b	DIVE_KINDS	;   and what the timer restarts from
DiveQueue	rs.b	DIVE_QUEUE*dq_SIZEOF	; a boss and those going with it, waiting to leave
BossBonus	rs.b	4		; dives: per boss, how many escorts it last left with
FormAlt		rs.w	FORM_ROWS	; formation: per row, bit n set if column n shows its row's other image
FormObj		rs.b	FORM_ROWS*HOME_COLUMNS	; which object has each place
Blasts		rs.b	BLASTS*bl_SIZEOF
Bombs		rs.b	BOMBS*bm_SIZEOF
FormBits	rs.b	HOME_ENTRIES	; breathing: per column and row, bit 0 set if it moves this step
StageLogPtr	rs.l	1		; STAGE_TEST builds: next free entry of the log
FlightFrame	rs.w	1		; flight: frames stepped; its low bit picks which speed a step uses
FighterX	rs.b	1		;   the fighter's x as the arcade's scripts see it: sprite x
StageHard	rs.b	1		;   nonzero: entry paths take their harder branch
StageHarder	rs.b	1		;   nonzero: dives take their harder branch
LastStand	rs.b	1		;   nonzero: one enemy left, attacking without pause
BossKilled	rs.b	1		;   the arcade's "capturing boss destroyed" task flag
StatePad	rs.b	1
HomeX		rs.b	32		; formation: pixel x of each column, low byte, in even entries
HomeLoc		rs.b	32		;   per column, then per row: its offset, its origin
Flights		rs.b	FLIGHT_SLOTS*fl_SIZEOF
WaveTable	rs.b	WAVE_BYTES	; launcher: the stage's waves, see stage.s
WavePlaces	rs.b	WAVE_PLACES	;   a wave being put together
RandomSeed	rs.w	1		; the random numbers' state
WaveCount	rs.b	1		; launcher: which wave is coming in, 1 to 5
TransformDone	rs.b	1		; transform: nonzero once the stage has had its one, or lost it
TransformTimer	rs.b	1		;   0 nobody picked; else counts up from $c0 to $ff while the one picked flashes
TransformKind	rs.b	1		;   what it becomes: KIND_GALAXIAN, KIND_SCORPION or KIND_BOSCONIAN
SpecialKind	rs.b	1		;   what it was
TrioLeft	rs.b	1		;   of it and the two that split off it: how many are still to shoot for the bonus
FlashImage	rs.l	1		;   its image in its new colours, wings open; wings closed follows
FormOther	rs.l	1		; formation: the other image of the row being composed
ObjKind		rs.b	OBJECTS/2	; what each enemy looks like (a KIND_ from gfx.i), by object / 2
Sound		rs.b	snd_SIZEOF	; the sound driver's state: see sound.i
State_SIZEOF	rs.b	0
