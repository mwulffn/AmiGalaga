; MEASURE build only: write stats (8 bytes) + the last frame to "results"
	lea	dosname(pc),a1
	jsr	OldOpenLibrary(a6)
	move.l	d0,a6
	lea	resname(pc),a0
	move.l	a0,d1
	move.l	#1006,d2		; MODE_NEWFILE
	jsr	-30(a6)			; Open
	move.l	d0,d4
	move.l	d4,d1
	lea	stats(pc),a0
	move.l	a0,d2
	moveq	#8,d3
	jsr	-48(a6)			; Write
	move.l	d4,d1
	move.l	a2,d2
	move.l	#SCRSIZE,d3
	jsr	-48(a6)
	move.l	d4,d1
	jsr	-36(a6)			; Close
	bra.s	mdone
dosname: dc.b	"dos.library",0
resname: dc.b	"results",0
	even
mdone:
