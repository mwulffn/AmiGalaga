; Startup and shutdown: take the machine from the operating system, run
; the game, give the machine back. The only file that calls the system.
;
; The best scores are read from disk before the machine is taken, and
; written back, if they have changed, after it has been given back: the
; game itself never touches the disk. The file is AmiGalaga.scores in
; the directory the game was started from. Everything about it may fail
; without the player hearing of it: no dos.library, no such file, a file
; of the wrong size or with a wrong checksum or with anything in it that
; is not a score or a letter (then the scores are the arcade's), a disk
; that is write protected, full or gone (then they are not saved). The
; system's requesters for such things are switched off for this process
; while the game runs, as they would show behind the game's display.
;
; Started from Workbench (its icon), the program has no shell: Workbench sends
; it a message instead, which must be taken before anything else is done and
; answered as the very last thing, and the directory the icon is in comes with
; the message, not as the current directory. So that is made the current
; directory while the program runs, and the best scores are beside the
; program however it was started.
;
; The sound driver takes CIA-B's timer A and switches the other CIA-B
; interrupts off; what the system had enabled there is asked of
; ciab.resource beforehand and put back afterwards.

	include	"config.i"
	include	"hw.i"
	include	"layout.i"
	include	"flight.i"
	include	"sound.i"
	include	"state.i"
	include	"macros.i"

	xdef	Start
	xref	Main
	xref	State

EXEC_BASE	equ	4
; exec.library
OldOpenLibrary	equ	-408
CloseLibrary	equ	-414
FindTask	equ	-294
WaitPort	equ	-384
GetMsg		equ	-372
ReplyMsg	equ	-378
pr_MsgPort	equ	92			; in the process: where Workbench's message comes
pr_CLI		equ	172			;   its shell, or 0 if Workbench started it
sm_ArgList	equ	36			; in Workbench's message: the program's directory (a lock) and name
OpenResource	equ	-498
pr_WindowPtr	equ	184			; in the process: where its requesters go; -1 for none
; cia.resource
AbleICR		equ	-18			; with no bits: changes nothing, returns what is enabled
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
Read		equ	-42
Write		equ	-48
CurrentDir	equ	-126
MODE_OLDFILE	equ	1005
MODE_NEWFILE	equ	1006
; the best scores' file: a mark, the scores and names as the state has them, a checksum
FILE_MARK	equ	'AGS1'
FILE_DATA	equ	SCORES*4+SCORES*NAME_BYTES
FILE_SIZE	equ	4+FILE_DATA+4

; Call a library routine through its base in a6. The system's convention:
; d0-d1 and a0-a1 are scratch, everything else is preserved.
CALLSYS	macro
	jsr	\1(a6)			; lint: clobbers d0-d1/a0-a1
	endm

	section	code,code

;--
; Start
; The program's entry point: must stay first in the first object linked.
; It owns a5 and a6 until it hands them to Main as the two reserved registers.
; lint: allow a5, a6
; In:       -
; Out:      d0 = 0, the return code for the shell
; Clobbers: d1-d7, a0-a6
Start:	move.l	EXEC_BASE.w,a6
	sub.l	a1,a1
	CALLSYS	FindTask
	move.l	d0,a2				; this process
	clr.l	WbMessage
	clr.b	AtHome
	tst.l	pr_CLI(a2)
	bne	.Shell
	lea	pr_MsgPort(a2),a0		; from Workbench: its message first
	CALLSYS	WaitPort
	lea	pr_MsgPort(a2),a0
	CALLSYS	GetMsg
	move.l	d0,WbMessage
.Shell	move.l	pr_WindowPtr(a2),OldWindow	; no requesters from here on
	moveq	#-1,d0
	move.l	d0,pr_WindowPtr(a2)
	lea	DosName(pc),a1
	CALLSYS	OldOpenLibrary
	move.l	d0,DosBase
	bsr	HomeDir
	move.l	EXEC_BASE.w,a6
	clr.b	CiaKnown
	lea	CiaName(pc),a1
	CALLSYS	OpenResource
	tst.l	d0
	beq	.NoCia
	move.l	a6,-(sp)
	move.l	d0,a6
	moveq	#0,d0
	CALLSYS	AbleICR
	move.l	(sp)+,a6
	move.b	d0,CiaMask
	st	CiaKnown
.NoCia	if	REPORTING=0
	bsr	ScoresLoad
	move.l	EXEC_BASE.w,a6
	endc
	lea	GfxName(pc),a1
	CALLSYS	OldOpenLibrary
	move.l	d0,a6
	move.l	gb_ActiView(a6),-(sp)
	move.l	a6,-(sp)
	sub.l	a1,a1
	CALLSYS	LoadView		; no view: the system's display is off
	CALLSYS	WaitTOF
	CALLSYS	WaitTOF
	move.l	EXEC_BASE.w,a6
	CALLSYS	Forbid
	; Stay in supervisor mode on this stack. Interrupts then push their
	; frames here, not on the system's supervisor stack in chip RAM, where
	; every access waits while the blitter has priority.
	CALLSYS	SuperState
	move.l	d0,-(sp)

	lea	CUSTOM,a6
	WAITBLIT
	move.b	CIAB_CRA,CiaControl
	move.w	intenar(a6),-(sp)
	move.w	dmaconr(a6),-(sp)
	move.w	#INT_ALL,intena(a6)
	move.w	#INT_ALL,intreq(a6)
	move.w	#DMA_ALL,dmacon(a6)
	lea	VEC_LEVEL1.w,a0		; subsystems install their own handlers
	lea	SavedVectors,a1
	moveq	#VEC_COUNT-1,d0
.Save	move.l	(a0)+,(a1)+
	dbf	d0,.Save

	lea	State,a5
	bsr	Main

	lea	CUSTOM,a6
	WAITBLIT
	move.w	#INT_ALL,intena(a6)
	move.w	#INT_ALL,intreq(a6)
	move.w	#DMA_ALL,dmacon(a6)
	lea	VEC_LEVEL1.w,a0
	lea	SavedVectors,a1
	moveq	#VEC_COUNT-1,d0
.Restore
	move.l	(a1)+,(a0)+
	dbf	d0,.Restore
	; CIA-B as the system had it: its timer A, and the interrupts it had enabled
	move.b	CiaControl,CIAB_CRA
	tst.b	CiaKnown
	beq	.NoMask
	move.b	#CIA_ICR_ALL,CIAB_ICR
	move.b	CiaMask,d0
	or.b	#CIA_ICR_SET,d0
	move.b	d0,CIAB_ICR
.NoMask
	move.w	(sp)+,d6		; dmacon and intena as the system had them,
	move.w	(sp)+,d7		; kept clear of the library calls' scratch registers
	move.l	(sp)+,d0
	move.l	EXEC_BASE.w,a6
	CALLSYS	UserState

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
	CALLSYS	LoadView
	CALLSYS	WaitTOF
	CALLSYS	WaitTOF
	move.l	a4,a1
	move.l	EXEC_BASE.w,a6
	CALLSYS	CloseLibrary
	CALLSYS	Permit

	if	REPORTING=0
	bsr	ScoresSave
	endc
	move.l	EXEC_BASE.w,a6
	sub.l	a1,a1
	CALLSYS	FindTask
	move.l	d0,a2
	move.l	OldWindow,pr_WindowPtr(a2)
	if	REPORTING
	move.l	DosBase,a6		; test build: leave the report for the host to read
	lea	ReportName(pc),a0
	move.l	a0,d1
	move.l	#MODE_NEWFILE,d2
	CALLSYS	Open
	move.l	d0,d4
	lea	State,a2
	move.l	d4,d1
	move.l	ReportPtr(a2),d2
	move.l	ReportLen(a2),d3
	CALLSYS	Write
	move.l	d4,d1
	CALLSYS	Close
	endc
	bsr	HomeDir				; the directory that was current, again
	move.l	EXEC_BASE.w,a6
	move.l	DosBase,d0
	beq	.NoDos
	move.l	d0,a1
	CALLSYS	CloseLibrary
.NoDos	move.l	WbMessage,d2
	beq	.Out
	CALLSYS	Forbid				; so that Workbench cannot unload the program
	move.l	d2,a1				;   before it has ended
	CALLSYS	ReplyMsg
.Out	moveq	#0,d0
	rts

;--
; HomeDir
; Started from Workbench: change the current directory. The first time to the program's
; own, which comes with Workbench's message; the second time back to the one that was
; current before. Started from a shell, or with no dos.library: nothing.
; lint: allow a6
; In:       -
; Out:      -
; Clobbers: d0-d1, a0-a1, a6
HomeDir:
	move.l	WbMessage,d0
	beq	.Done
	move.l	d0,a0
	move.l	DosBase,d0
	beq	.Done
	move.l	d0,a6
	move.l	OtherDir,d1
	not.b	AtHome
	beq	.Change				; it was at home: back
	move.l	sm_ArgList(a0),a0
	move.l	(a0),d1				; the first argument's lock: the program's directory
.Change	CALLSYS	CurrentDir
	move.l	d0,OtherDir			; the one that was current
.Done	rts

	if	REPORTING=0
;--
; ScoresLoad
; Read the best scores from disk into the state, if there is a file and all of it is good.
; lint: allow a6
; In:       -
; Out:      -
; Clobbers: d0-d5, a0-a1, a6
ScoresLoad:
	move.l	DosBase,d0
	beq	.None
	move.l	d0,a6
	lea	ScoresName(pc),a0
	move.l	a0,d1
	move.l	#MODE_OLDFILE,d2
	CALLSYS	Open
	move.l	d0,d4
	beq	.None
	move.l	d4,d1
	move.l	#FileBuffer,d2
	moveq	#FILE_SIZE,d3
	CALLSYS	Read
	move.l	d0,d5
	move.l	d4,d1
	CALLSYS	Close
	moveq	#FILE_SIZE,d0
	cmp.l	d0,d5
	bne	.None
	lea	FileBuffer,a0
	bsr	ScoresGood
	beq	.None
	lea	FileBuffer+4,a0
	lea	State+Scores,a1
	moveq	#FILE_DATA-1,d0
.Copy	move.b	(a0)+,(a1)+
	dbf	d0,.Copy
	st	State+ScoresLoaded
.None	rts

;--
; ScoresGood
; Is a file's content a set of best scores? Its mark and checksum must be right, every
; score six decimal digits, and every name three of the letters initials are made of.
; In:       a0 = the file's FILE_SIZE bytes
; Out:      Z = no
; Clobbers: d0-d3, a0-a1
ScoresGood:
	cmp.l	#FILE_MARK,(a0)
	bne	.Bad
	move.l	a0,a1
	bsr	FileSum
	cmp.l	(a1),d0
	bne	.Bad
	addq.l	#4,a0
	moveq	#SCORES-1,d2
.Score	move.l	(a0)+,d0
	moveq	#8-1,d3
.Digit	moveq	#15,d1
	and.w	d0,d1
	cmp.w	#2,d3				; from the lowest: the top two of the eight must be 0,
	bcc	.Decimal
	tst.w	d1
	bne	.Bad
.Decimal
	cmp.w	#9,d1				;   the others at most 9
	bhi	.Bad
	ror.l	#4,d0
	dbf	d3,.Digit
	dbf	d2,.Score
	moveq	#SCORES-1,d2
.Name	moveq	#NAME_BYTES-2,d3
.Letter	move.b	(a0)+,d0
	cmp.b	#' ',d0
	beq	.Fine
	cmp.b	#'.',d0
	beq	.Fine
	cmp.b	#'A',d0
	bcs	.Bad
	cmp.b	#'Z',d0
	bhi	.Bad
.Fine	dbf	d3,.Letter
	tst.b	(a0)+
	bne	.Bad
	dbf	d2,.Name
	moveq	#1,d0
	rts
.Bad	moveq	#0,d0
	rts

;--
; FileSum
; The checksum of a file's content: its longs before the last, added up.
; In:       a1 = the file's FILE_SIZE bytes
; Out:      d0.l = the sum, a1 = where the file has its own
; Clobbers: d1
FileSum:
	moveq	#0,d0
	moveq	#(FILE_SIZE-4)/4-1,d1
.Long	add.l	(a1)+,d0
	dbf	d1,.Long
	rts

;--
; ScoresSave
; Write the best scores to disk, if they have changed. If the file cannot be made or
; written, they are not saved, and that is all.
; lint: allow a6
; In:       -
; Out:      -
; Clobbers: d0-d4, a0-a1, a6
ScoresSave:
	tst.b	State+ScoresDirty
	beq	.Done
	move.l	DosBase,d0
	beq	.Done
	move.l	d0,a6
	lea	FileBuffer,a1
	move.l	#FILE_MARK,(a1)+
	lea	State+Scores,a0
	moveq	#FILE_DATA-1,d0
.Copy	move.b	(a0)+,(a1)+
	dbf	d0,.Copy
	lea	FileBuffer,a1
	bsr	FileSum
	move.l	d0,(a1)
	lea	ScoresName(pc),a0
	move.l	a0,d1
	move.l	#MODE_NEWFILE,d2
	CALLSYS	Open
	move.l	d0,d4
	beq	.Done
	move.l	d4,d1
	move.l	#FileBuffer,d2
	moveq	#FILE_SIZE,d3
	CALLSYS	Write
	move.l	d4,d1
	CALLSYS	Close
.Done	rts
	endc

GfxName:	dc.b	"graphics.library",0
DosName:	dc.b	"dos.library",0
CiaName:	dc.b	"ciab.resource",0
	if	REPORTING
ReportName:	dc.b	"results",0
	else
ScoresName:	dc.b	"AmiGalaga.scores",0
	endc
	even

	section	bss,bss
SavedVectors:	ds.l	VEC_COUNT
DosBase:	ds.l	1
OldWindow:	ds.l	1			; the process's pr_WindowPtr, to put back
WbMessage:	ds.l	1			; Workbench's message if it started the program, else 0
OtherDir:	ds.l	1			; started from Workbench: the directory that was current before
FileBuffer:	ds.b	FILE_SIZE		; the best scores' file as read or to be written
CiaMask:	ds.b	1			; the CIA-B interrupts the system had enabled
CiaControl:	ds.b	1			;   and its timer A's control register
CiaKnown:	ds.b	1			;   nonzero if ciab.resource told us
AtHome:		ds.b	1			; nonzero while the current directory is the program's own
	even
