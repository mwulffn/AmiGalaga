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
