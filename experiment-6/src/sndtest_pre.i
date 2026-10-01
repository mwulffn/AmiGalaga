; SNDTEST: apply this tick's script entries (tick, offset in snd_state, value)
	lea	testvars(pc),a0
	move.w	(a0),d0
	move.l	2(a0),a1
	lea	snd_state,a2
.ev	cmp.w	(a1),d0
	bne.s	.go
	moveq	#0,d1
	move.b	2(a1),d1
	move.b	3(a1),(a2,d1.w)
	addq.l	#4,a1
	bra.s	.ev
.go	move.l	a1,2(a0)
