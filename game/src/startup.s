; Startup and shutdown: take the machine from the operating system, run
; the game, give the machine back. The only file that calls the system.

	include	"config.i"
	include	"hw.i"
	include	"state.i"
	include	"macros.i"

	xdef	Start
	xref	Main
	xref	State

EXEC_BASE	equ	4
; exec.library
OldOpenLibrary	equ	-408
CloseLibrary	equ	-414
Forbid		equ	-132
Permit		equ	-138
SuperState	equ	-150
UserState	equ	-156
; graphics.library
LoadView	equ	-222
WaitTOF		equ	-270
gb_ActiView	equ	34
gb_copinit	equ	38
gb_LOFlist	equ	50
; dos.library
Open		equ	-30
Close		equ	-36
Write		equ	-48
MODE_NEWFILE	equ	1006

	section	code,code

;--
; Start
; The program's entry point: must stay first in the first object linked.
; In:       -
; Out:      d0 = 0, the return code for the shell
; Clobbers: d1-d7, a0-a6
Start:	move.l	EXEC_BASE.w,a6
	lea	GfxName(pc),a1
	jsr	OldOpenLibrary(a6)
	move.l	d0,a6
	move.l	gb_ActiView(a6),-(sp)
	move.l	a6,-(sp)
	sub.l	a1,a1
	jsr	LoadView(a6)		; no view: the system's display is off
	jsr	WaitTOF(a6)
	jsr	WaitTOF(a6)
	move.l	EXEC_BASE.w,a6
	jsr	Forbid(a6)
	; Stay in supervisor mode on this stack. Interrupts then push their
	; frames here, not on the system's supervisor stack in chip RAM, where
	; every access waits while the blitter has priority.
	jsr	SuperState(a6)
	move.l	d0,-(sp)

	lea	CUSTOM,a6
	WAITBLIT
	move.w	intenar(a6),-(sp)
	move.w	dmaconr(a6),-(sp)
	move.w	#INT_ALL,intena(a6)
	move.w	#INT_ALL,intreq(a6)
	move.w	#DMA_ALL,dmacon(a6)
	lea	VEC_LEVEL1.w,a0		; subsystems install their own handlers
	moveq	#VEC_COUNT-1,d0
.Save	move.l	(a0)+,-(sp)
	dbf	d0,.Save

	lea	State,a5
	bsr	Main

	lea	CUSTOM,a6
	WAITBLIT
	move.w	#INT_ALL,intena(a6)
	move.w	#INT_ALL,intreq(a6)
	move.w	#DMA_ALL,dmacon(a6)
	lea	VEC_LEVEL1+VEC_COUNT*4.w,a0
	moveq	#VEC_COUNT-1,d0
.Restore
	move.l	(sp)+,-(a0)
	dbf	d0,.Restore
	move.w	(sp)+,d6		; dmacon and intena as the system had them,
	move.w	(sp)+,d7		; kept clear of the library calls' scratch registers
	move.l	(sp)+,d0
	move.l	EXEC_BASE.w,a6
	jsr	UserState(a6)

	move.l	(sp)+,a4		; graphics.library
	lea	CUSTOM,a6
	move.l	gb_copinit(a4),cop1lc(a6)
	move.l	gb_LOFlist(a4),cop2lc(a6)
	or.w	#DMA_SET,d6
	or.w	#INT_SET|INT_MASTER,d7
	move.w	d6,dmacon(a6)
	move.w	d7,intena(a6)
	move.l	a4,a6
	move.l	(sp)+,a1
	jsr	LoadView(a6)
	jsr	WaitTOF(a6)
	jsr	WaitTOF(a6)
	move.l	a4,a1
	move.l	EXEC_BASE.w,a6
	jsr	CloseLibrary(a6)
	jsr	Permit(a6)

	if	TEST_FRAMES
	lea	DosName(pc),a1		; test build: leave the report for the host to read
	jsr	OldOpenLibrary(a6)
	move.l	d0,a6
	lea	ReportName(pc),a0
	move.l	a0,d1
	move.l	#MODE_NEWFILE,d2
	jsr	Open(a6)
	move.l	d0,d4
	lea	State,a2
	move.l	d4,d1
	move.l	ReportPtr(a2),d2
	move.l	ReportLen(a2),d3
	jsr	Write(a6)
	move.l	d4,d1
	jsr	Close(a6)
	endc
	moveq	#0,d0
	rts

GfxName:	dc.b	"graphics.library",0
	if	TEST_FRAMES
DosName:	dc.b	"dos.library",0
ReportName:	dc.b	"results",0
	endc
	even
