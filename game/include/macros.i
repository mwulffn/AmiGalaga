; Wait until the blitter is free. Uses a6 = CUSTOM. The first read is a
; dummy: the busy flag is not valid on the first read after a blit starts.
WAITBLIT	macro
	tst.b	dmaconr(a6)
.wb\@	btst	#DMAB_BLTBUSY,dmaconr(a6)
	bne	.wb\@
	endm
