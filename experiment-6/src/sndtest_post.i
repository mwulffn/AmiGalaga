; SNDTEST: log what this tick sent to the three voices: periods, volumes, waveforms
	lea	testvars(pc),a0
	cmp.w	#SNDTEST,(a0)
	bcc.s	.full
	addq.w	#1,(a0)
	move.l	6(a0),a1
	lea	snd_state,a2
	move.w	s_per(a2),(a1)+
	move.w	s_per+2(a2),(a1)+
	move.w	s_per+4(a2),(a1)+
	moveq	#3-1,d1
.vol	moveq	#15,d0
	and.b	s_vol(a2),d0
	move.b	d0,(a1)+
	addq.l	#1,a2
	dbf	d1,.vol
	moveq	#3-1,d1
.wav	moveq	#7,d0
	and.b	s_wave-3(a2),d0
	move.b	d0,(a1)+
	addq.l	#1,a2
	dbf	d1,.wav
	move.l	a1,6(a0)
.full
