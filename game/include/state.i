; The game state. A5 holds its address everywhere; fields are used as Name(a5).
; Include config.i, layout.i, flight.i and sound.i first.

	rsreset
FrameCount	rs.w	1		; vertical blanks since start
FrontScreen	rs.l	1		; the screen being shown (a scr_ structure)
BackScreen	rs.l	1		; the screen being drawn
StarFirst	rs.w	1		; star table entry shown on the first line, 0-255
StarSpeed	rs.w	1		; lines the stars scroll per frame
StarFade	rs.l	1		; next entry of the fade schedule
ReportPtr	rs.l	1		; test builds: what to write to "results"
ReportLen	rs.l	1
FrameStart	rs.w	1		; test builds: FrameCount when this frame's work began
StatWorst	rs.w	1		; test builds: most raster lines a frame's work took
StatTotal	rs.l	1		;   their sum
StatFrames	rs.w	1		;   and how many frames
STAT_SIZE	equ	8
FormRows	rs.w	2*FORM_ROWS	; formation: per row, x and y of its strip, set when composed
FormPresent	rs.w	FORM_ROWS	;   per row: bit n set if the enemy in column n is there
Score		rs.l	1		; six decimal digits, two to a byte, in the low three bytes
ScoreText	rs.b	8		; scratch for printing it
ShipX		rs.w	1		; the fighter, in playfield pixels
Bullets		rs.w	4		; x, y of each of its two bullets; y < 0: not there
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
Sound		rs.b	snd_SIZEOF	; the sound driver's state: see sound.i
State_SIZEOF	rs.b	0
