; Wait until the blitter is free. Uses a6 = CUSTOM. The first read is a
; dummy: the busy flag is not valid on the first read after a blit starts.
WAITBLIT	macro
	tst.b	dmaconr(a6)
.wb\@	btst	#DMAB_BLTBUSY,dmaconr(a6)
	bne	.wb\@
	endm

; Ask the sound driver for a sound: \1 = its SND_ name. Uses a5 = state.
; A SOUND_TEST build makes its own requests.
SOUND	macro
	if	SOUND_TEST=0
	move.b	#1,Sound+\1(a5)
	endc
	endm

; A STAGE_TEST build's log: \1 = what happened (a STAGE_ or FLIGHT_ name), \2 = the byte
; that goes with it. Uses a5 = state and the stack; the arguments may use any register.
LOG	macro
	if	STAGE_TEST
	move.b	\2,-(sp)
	move.b	\1,-(sp)
	move.l	a0,-(sp)
	move.l	StageLogPtr(a5),a0
	move.w	FlightFrame(a5),(a0)+
	move.b	4(sp),(a0)+
	move.b	6(sp),(a0)+
	move.l	a0,StageLogPtr(a5)
	move.l	(sp)+,a0
	addq.l	#4,sp
	endc
	endm

; A PROFILE build's profile: note how far into the frame the work has come. \1 = which mark,
; a PROF_ name. Uses a5 = state and a6 = CUSTOM. A blit is waited for before the next one
; starts, so the last blit of one part is paid for in the next.
MARK	macro
	if	PROFILE
	move.l	d0,-(sp)
	move.w	FrameCount(a5),d0
	sub.w	FrameStart(a5),d0
	mulu.w	#PAL_LINES,d0
	move.w	d0,ProfMarks+2*\1(a5)
	move.l	vposr(a6),d0
	lsr.l	#8,d0
	and.w	#$1ff,d0
	add.w	d0,ProfMarks+2*\1(a5)
	move.l	(sp)+,d0
	endc
	endm
