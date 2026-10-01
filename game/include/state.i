; The game state. A5 holds its address everywhere; fields are used as Name(a5).

	rsreset
FrameCount	rs.w	1		; vertical blanks since start
FrontBuffer	rs.l	1		; the screen being shown
BackBuffer	rs.l	1		; the screen being drawn
ReportPtr	rs.l	1		; test builds: what to write to "results"
ReportLen	rs.l	1
FrameStart	rs.w	1		; test builds: FrameCount when this frame's work began
StatWorst	rs.w	1		; test builds: most raster lines a frame's work took
StatTotal	rs.l	1		;   their sum
StatFrames	rs.w	1		;   and how many frames
STAT_SIZE	equ	8
State_SIZEOF	rs.b	0
