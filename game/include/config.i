; Compile-time switches. Defaults are the release build; override on the
; command line, for example: make DEFS="-DRASTER_METER=1"

	ifnd	RASTER_METER
RASTER_METER	equ	0		; 1: background turns blue once the frame's work is done
	endc

	ifnd	TEST_FRAMES
TEST_FRAMES	equ	0		; n: run n frames, exit, write the report to "results"
	endc

	ifnd	BLITTER_PRIORITY
BLITTER_PRIORITY equ	1		; 1: the blitter takes the bus ahead of the CPU
	endc

	ifnd	SOUND_TEST
SOUND_TEST	equ	0		; n: drive the sound driver from the test script for n
	endc				;    ticks and report what it sent to Paula

	ifnd	EXACT_TIMING
EXACT_TIMING	equ	0		; 1: enemies move one arcade frame per displayed frame,
	endc				;    byte for byte as in the arcade (and so 17% slow on PAL)

	ifnd	FLIGHT_TEST
FLIGHT_TEST	equ	0		; 1: fly the test cases, report every position, and exit
	endc

	ifnd	STAGE_TEST
STAGE_TEST	equ	0		; 1: with TEST_FRAMES, report every launch and landing
	endc

	ifnd	RANK
RANK		equ	3		; the arcade's difficulty switch: which row of the stage
	endc				;    index it uses. 3 is the arcade's (and MAME's) default

	ifnd	DEMO_STAGES
DEMO_STAGES	equ	3		; until there is a game: the stages it cycles through
	endc

; a build that writes a report for the host
REPORTING	equ	TEST_FRAMES+SOUND_TEST+FLIGHT_TEST
