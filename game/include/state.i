; The game state. A5 holds its address everywhere; fields are used as Name(a5).
; Include config.i, layout.i and sound.i first.

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
FormSway	rs.w	1		; formation: pixels right of its leftmost position
FormSpread	rs.w	1		;   how far it has spread: 0 closed
FormRows	rs.w	2*FORM_ROWS	;   per row: x and y of its strip, set when composed
Sound		rs.b	snd_SIZEOF	; the sound driver's state: see sound.i
State_SIZEOF	rs.b	0
