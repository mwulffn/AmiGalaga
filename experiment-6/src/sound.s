;----------------------------------------------------------------------
; The arcade's sound driver on Paula.
;
; A port of sound/native.py, which is tick-for-tick identical to the
; arcade. A CIA timer calls snd_tick 121 times a second, as in the
; arcade. Each tick the three voices start silent, the sounds that are
; playing are advanced in a fixed order (later ones overwrite the voices
; of earlier ones), and the result is written to Paula channels 0-2 as a
; period, a volume and one of the arcade's eight waveforms. Channel 3
; plays the fighter explosion: a noise loop with a decaying volume.
;
; To request sound n, write to byte 2*n of snd_state: a count, or on/off
; for the held sounds. Also s_dir for the formation's direction ($ff
; closing, anything else opening) and s_bang for the explosion.
;
;   bsr snd_init    with the custom chips owned; starts the timer
;   bsr snd_stop    before giving the machine back
;----------------------------------------------------------------------

CIAB_ICR  equ	$bfdd00
CIAB_TALO equ	$bfd400
CIAB_TAHI equ	$bfd500
CIAB_CRA  equ	$bfde00
TICK_E	equ	5852			; 709379 Hz / 5852 = 121.2 ticks a second

aud0	equ	$0a0			; + $10 per channel: lc.l, len.w, per.w, vol.w
NOISE_PER equ	443			; 8 kHz
NOISE_LEN equ	4000
BANG_TICKS equ	324			; 2.67 s
BANG_HOLD equ	27			; full level for 0.22 s
BANG_DECAY equ	64833			; then x 0.98927 per tick: halves every 0.53 s

; snd_state layout
					; 0-63: per sound, a request byte written by
					; the game, then a byte that is set while it plays
s_vol	equ	64			; 3 voices
s_wave	equ	67			; 3, kept between ticks
s_fin	equ	70			; a track hit its end this tick
s_dir	equ	71			; formation direction, written by the game
s_bang	equ	72			; explosion request, written by the game
s_pdir	equ	73			; formation pulse: last direction seen
s_pstep	equ	74
s_bvol	equ	75			; tractor beam: voice 2 volume, its timer
s_btick	equ	76
s_bwave	equ	77			; capture: voice 0 waveform, its timer
s_bwtick equ	78
s_quiet	equ	79			; the three voices were silent last tick
s_per	equ	80			; 3 words: Paula period | length code << 12
s_ptab	equ	86			; pulse: 0 opening, 16 closing
s_prate	equ	88
s_ppitch equ	90
s_gain	equ	92			; explosion: level, ticks left
s_left	equ	94
s_last	equ	96			; per voice: period entry and waveform last sent to Paula
s_trk	equ	108			; 48 tracks of T_SIZE bytes
T_SIZE	equ	8
t_clock	equ	0			; ticks into the current note
t_pos	equ	1			; offset of the current (note, length) pair
t_env	equ	2			; envelope type from the track header; $ff for a rest
t_delay	equ	3			; envelope delay from the header
t_wave	equ	4			; waveform from the header
t_dur	equ	5			; ticks this note lasts
t_per	equ	6			; its Paula period | length code << 12
S_SIZE	equ	s_trk+48*T_SIZE

; handle one sound if it is requested or playing
SND	macro
	tst.w	2*\1(a5)
	beq.s	.s\@
	moveq	#\1,d7
	moveq	#\2,d6
	lea	2*\1(a5),a4
	bsr	handle
.s\@
	endm

snd_init:
	lea	snd_state,a0
	moveq	#S_SIZE/4-1,d0
.clr	clr.l	(a0)+
	dbf	d0,.clr
	lea	CUSTOM+aud0,a0
	moveq	#3-1,d0
.chan	move.l	#snd_waves,(a0)		; any waveform, silent
	move.w	#16,4(a0)
	move.w	#400,6(a0)
	clr.w	8(a0)
	lea	$10(a0),a0
	dbf	d0,.chan
	move.l	#snd_noise,(a0)
	move.w	#NOISE_LEN/2,4(a0)
	move.w	#NOISE_PER,6(a0)
	clr.w	8(a0)
	move.w	#$800f,CUSTOM+dmacon	; audio DMA on
	move.b	#$7f,CIAB_ICR		; no CIA-B interrupts but ours
	move.b	#TICK_E&255,CIAB_TALO
	move.b	#TICK_E>>8,CIAB_TAHI
	move.b	#$81,CIAB_ICR		; timer A
	move.b	#$11,CIAB_CRA		; load, run continuously
	rts

snd_stop:
	move.b	#$00,CIAB_CRA
	move.b	#$01,CIAB_ICR
	lea	CUSTOM,a0
	moveq	#0,d0
	move.w	d0,aud0+$08(a0)
	move.w	d0,aud0+$18(a0)
	move.w	d0,aud0+$28(a0)
	move.w	d0,aud0+$38(a0)
	move.w	#$000f,dmacon(a0)
	rts

; level 6 interrupt: the CIA timer
snd_int:
	movem.l	d0-d7/a0-a6,-(sp)
	tst.b	CIAB_ICR		; reading acknowledges
	ifd	MEASURE
	move.l	CUSTOM+vposr,-(sp)
	endc
	ifd	SNDTEST
	include	"sndtest_pre.i"
	endc
	bsr	snd_tick
	ifd	SNDTEST
	include	"sndtest_post.i"
	endc
	ifd	MEASURE
	move.l	CUSTOM+vposr,d0		; beam position: line << 8 | colour clock
	move.l	(sp)+,d1
	and.l	#$1ffff,d0
	and.l	#$1ffff,d1
	move.l	d0,d2
	lsr.l	#8,d2
	move.l	d1,d3
	lsr.l	#8,d3
	sub.w	d3,d2			; lines
	bpl.s	.pos
	add.w	#313,d2
.pos	mulu	#227,d2
	and.w	#$ff,d0
	and.w	#$ff,d1
	sub.w	d1,d0
	add.w	d0,d2			; colour clocks this tick took
	lea	tickstats(pc),a0
	cmp.w	(a0),d2
	bls.s	.nomax
	move.w	d2,(a0)
.nomax	ext.l	d2
	add.l	d2,2(a0)
	addq.w	#1,6(a0)
	endc
	move.w	#$2000,CUSTOM+intreq
	movem.l	(sp)+,d0-d7/a0-a6
	rte

;----------------------------------------------------------------------
; One driver tick.
; a5 = state, a2 = tracks, a6 = note table
snd_tick:
	lea	snd_state,a5
	lea	s_trk(a5),a2
	lea	snd_notes(pc),a6
	clr.w	s_vol(a5)
	clr.b	s_vol+2(a5)
	clr.l	s_per(a5)
	clr.w	s_per+4(a5)
	tst.b	(a5)
	beq.s	.nopulse
	bsr	slide
.nopulse
	; every sound in the arcade's order; one that is neither requested
	; nor playing costs a test and a branch
	SND	$13,0
	SND	$0f,0
	SND	$03,0
	SND	$02,0
	SND	$04,0
	SND	$01,0
	SND	$12,1
	SND	$05,2
	SND	$06,2
	SND	$09,2
	SND	$07,1
	SND	$11,2
	SND	$0d,1
	SND	$0e,1
	SND	$14,1
	SND	$15,1
	SND	$0a,1
	SND	$0b,1
	SND	$10,2
	SND	$0c,1
	SND	$16,1
	SND	$08,1
	bra	to_paula

; d7 = sound, d6 = how its request works (0 trigger, 1 count, 2 held), a4 = its request/active pair
handle:	tst.b	d6
	bne.s	.gated
	tst.b	(a4)			; trigger: the request starts it, then it runs by itself
	beq.s	.running
	clr.b	(a4)
	addq.b	#1,1(a4)
	moveq	#1,d5
	bra	play
.running
	moveq	#0,d5
	bra	play
.gated	tst.b	(a4)			; count and held: plays while requested
	bne.s	.on
	clr.b	1(a4)
	rts
.on	moveq	#0,d5
	tst.b	1(a4)
	bne.s	.go
	move.b	#1,1(a4)
	moveq	#1,d5
.go	bsr	play
	beq.s	.extras
	subq.b	#1,d6
	bne.s	.extras
	cmp.b	#$08,d7			; a counted sound ended
	beq.s	.coin
	cmp.b	#$0c,d7
	beq.s	.name
	clr.b	(a4)
	cmp.b	#$14,d7
	bne.s	.extras
	move.b	#1,2*$13(a5)		; "perfect" is followed by the dive sound
	bra.s	.extras
.name	subq.b	#1,(a4)			; name entry alternates with sound $16
	beq.s	.other
	btst	#0,(a4)
	beq.s	.extras
.other	move.b	#1,2*$16(a5)
	bra.s	.extras
.coin	subq.b	#1,(a4)			; once per credit
.extras	cmp.b	#$05,d7
	beq.s	.beam
	cmp.b	#$06,d7
	beq.s	.capture
	cmp.b	#$0e,d7
	bne.s	.done
	move.b	#9,s_vol+1(a5)		; results tune: fixed volumes
	move.b	#6,s_vol+2(a5)
.done	rts
.beam	addq.b	#1,s_btick(a5)		; tractor beam: voice 2's volume sweeps down and wraps
	cmp.b	#6,s_btick(a5)
	bcs.s	.bvol
	clr.b	s_btick(a5)
	move.b	s_bvol(a5),d0
	subq.b	#1,d0
	cmp.b	#3,d0
	bcs.s	.wrap			; was 1-3
	cmp.b	#$ff,d0
	bne.s	.bset			; was 0
.wrap	moveq	#$0c,d0
.bset	move.b	d0,s_bvol(a5)
.bvol	move.b	s_bvol(a5),s_vol+2(a5)
	rts
.capture
	addq.b	#1,s_bwtick(a5)		; capture: voice 0 steps through the waveforms
	cmp.b	#$1c,s_bwtick(a5)
	bne.s	.cwave
	clr.b	s_bwtick(a5)
	addq.b	#1,s_bwave(a5)
.cwave	move.b	s_bwave(a5),s_wave(a5)
	rts

; Paula volume for the arcade's 16 levels. The explosion plays at 64; in
; the arcade it is about 10 dB louder than the start theme, and tones at
; 1.5 x level leave it about 10.7 dB louder here.
tonevol: dc.b	0,2,3,5,6,8,9,11,12,14,15,17,18,20,21,23

; write the three voices and the explosion to Paula
to_paula: move.b	s_vol(a5),d0
	or.b	s_vol+1(a5),d0
	or.b	s_vol+2(a5),d0
	bne.s	.send
	tst.b	s_quiet(a5)		; silent, and Paula already told so
	bne	.bang
.send	tst.b	d0
	seq	s_quiet(a5)
	lea	CUSTOM+aud0,a0
	lea	s_per(a5),a1
	lea	s_last(a5),a3
	moveq	#0,d6			; voice
.voice	moveq	#15,d0
	and.b	s_vol(a5,d6.w),d0
	move.w	(a1)+,d1
	bne.s	.sounding
	moveq	#0,d0
.sounding
	move.b	tonevol(pc,d0.w),d0
	move.w	d0,8(a0)
	beq.s	.silent
	moveq	#7,d3
	and.b	s_wave(a5,d6.w),d3
	cmp.w	(a3),d1			; same note and waveform as last time?
	bne.s	.change
	cmp.b	2(a3),d3
	beq.s	.silent
.change	move.w	d1,(a3)
	move.b	d3,2(a3)
	move.w	d1,d2
	and.w	#$0fff,d2
	move.w	d2,6(a0)		; period
	rol.w	#4,d1
	and.w	#3,d1			; length code: 32, 16, 8 samples
	moveq	#5,d4
	sub.w	d1,d4
	lsl.w	d4,d3			; waveform * length
	move.w	d1,d4
	add.w	d4,d4
	add.w	wavebase(pc,d4.w),d3
	lea	snd_waves,a4
	add.w	d3,a4
	move.l	a4,(a0)			; Paula picks these up when the current pass ends
	moveq	#16,d4
	lsr.w	d1,d4
	move.w	d4,4(a0)
.silent	lea	$10(a0),a0
	addq.l	#4,a3
	addq.w	#1,d6
	cmp.w	#3,d6
	bne.s	.voice

.bang	lea	CUSTOM+aud0+$30,a0
	tst.b	s_bang(a5)		; explosion: full level, then a steady halving
	beq.s	.nobang
	clr.b	s_bang(a5)
	move.w	#$ffff,s_gain(a5)
	move.w	#BANG_TICKS,s_left(a5)
.nobang	moveq	#0,d1
	move.w	s_left(a5),d0
	beq.s	.noise
	subq.w	#1,d0
	move.w	d0,s_left(a5)
	move.w	s_gain(a5),d1
	cmp.w	#BANG_TICKS-BANG_HOLD,d0
	bcc.s	.level
	mulu	#BANG_DECAY,d1
	swap	d1
	move.w	d1,s_gain(a5)
.level	lsr.w	#8,d1
	lsr.w	#2,d1
	addq.w	#1,d1			; 1-64
.noise	move.w	d1,8(a0)
	rts

wavebase: dc.w	0,8*32,8*32+8*16

; d7 = sound, d5 = start from the top. Returns nonzero (and Z clear) when it ended.
play:	move.w	d7,d0
	add.w	d0,d0
	add.w	d7,d0
	lea	snd_parms(pc),a0
	add.w	d0,a0
	moveq	#0,d1
	move.b	(a0)+,d1		; first track
	moveq	#0,d2
	move.b	(a0)+,d2		; tracks
	moveq	#0,d3
	move.b	(a0),d3			; first voice
	cmp.b	#$0e,d7			; the results tune brings its voices in one at a time
	bne.s	.count
	tst.b	$1c*T_SIZE+t_pos(a2)
	beq.s	.one
	cmp.b	#1,$1c*T_SIZE+t_pos(a2)
	beq.s	.two
	tst.b	$1d*T_SIZE+t_pos(a2)
	bne.s	.count
.two	moveq	#2,d2
	bra.s	.count
.one	moveq	#1,d2
.count	subq.w	#1,d2
	tst.b	d5
	beq.s	.track
	move.w	d1,d0
	lsl.w	#3,d0
	lea	(a2,d0.w),a0
	move.w	d2,d0
.rewind	clr.w	(a0)			; clock and position
	addq.l	#T_SIZE,a0
	dbf	d0,.rewind
.track	bsr.s	track
	addq.w	#1,d1
	addq.w	#1,d3
	dbf	d2,.track
	move.b	s_fin(a5),d0
	beq.s	.ret
	clr.b	s_fin(a5)
	clr.b	1(a4)
	moveq	#1,d0
.ret	rts

; advance one track by a tick: d7 = sound, d1 = track, d3 = voice
track:	move.w	d1,d0
	lsl.w	#3,d0
	lea	(a2,d0.w),a0
	addq.b	#1,(a0)
	moveq	#0,d4
	move.b	(a0),d4			; ticks into this note
	cmp.b	#1,d4
	bne.s	.playing
	move.w	d1,d0			; first tick of a note: look everything up once
	add.w	d0,d0
	lea	snd_trackptr(pc),a1
	move.w	(a1,d0.w),d0
	lea	snd_tracks(pc),a1
	add.w	d0,a1
	move.b	(a1)+,t_env(a0)		; header: envelope, delay, waveform
	move.b	(a1)+,t_delay(a0)
	move.b	(a1)+,t_wave(a0)
	moveq	#0,d0
	move.b	t_pos(a0),d0
	add.w	d0,a1			; the (note, length) pair
	moveq	#0,d0
	move.b	(a1)+,d0
	cmp.b	#$ff,d0
	bne.s	.note
	clr.b	(a0)			; the end: look again next tick
	clr.b	s_vol(a5,d3.w)
	st	s_fin(a5)
	rts
.note	cmp.b	#$0c,d0
	bne.s	.pitch
	st	t_env(a0)		; a rest
.pitch	add.w	d0,d0
	move.w	(a6,d0.w),t_per(a0)
	moveq	#0,d0
	move.b	(a1),d0
	moveq	#0,d5
	lea	snd_tempo(pc),a1
	move.b	(a1,d7.w),d5
	mulu	d5,d0
	move.b	d0,t_dur(a0)
.playing
	move.w	d3,d5
	add.w	d5,d5
	move.w	t_per(a0),s_per(a5,d5.w)
	move.b	t_env(a0),d5
	beq.s	.steady
	bmi.s	.mute
	cmp.b	#6,d4
	bcc.s	.steady
	subq.b	#1,d5
	bne.s	.sharp
	move.b	d4,d5			; envelope 1: fade in
	add.b	d5,d5
	bra.s	.set
.sharp	move.b	d4,d5			; envelope 2: 14, 13, ... a sharp start
	not.b	d5
	bra.s	.set
.steady	moveq	#10,d5
	moveq	#0,d0
	move.b	t_delay(a0),d0		; fade out once past the delay, if there is one
	beq.s	.set
	sub.w	d4,d0
	bhi.s	.set
	add.w	d0,d5
	bpl.s	.set
.mute	moveq	#0,d5
.set	move.b	d5,s_vol(a5,d3.w)
	move.b	t_wave(a0),s_wave(a5,d3.w)
	cmp.b	t_dur(a0),d4		; note over?
	bne.s	.same
	addq.b	#2,t_pos(a0)
	clr.b	(a0)
.same	rts

; request 0: voice 0 slides up while the formation opens, down while it closes
slide:	move.b	s_dir(a5),d0
	cmp.b	s_pdir(a5),d0
	beq.s	.same
	move.b	d0,s_pdir(a5)
	moveq	#0,d1
	addq.b	#1,d0
	bne.s	.open
	moveq	#16,d1
.open	move.w	d1,s_ptab(a5)
	clr.b	(a2)			; track 0's clock is the pulse's own
	clr.b	s_pstep(a5)
	bra.s	.load
.same	addq.b	#1,(a2)
	cmp.b	#$22,(a2)
	bne.s	.slide
	clr.b	(a2)
	addq.b	#1,s_pstep(a5)
.load	moveq	#0,d0
	move.b	s_pstep(a5),d0
	add.w	d0,d0
	add.w	s_ptab(a5),d0
	lea	snd_pulse(pc),a0
	add.w	d0,a0
	move.w	(a0),s_prate(a5)
	move.w	$20(a0),s_ppitch(a5)
.slide	move.w	s_ppitch(a5),d0
	add.w	s_prate(a5),d0
	move.w	d0,s_ppitch(a5)
	lsr.w	#8,d0
	add.w	d0,d0
	lea	snd_pulseper(pc),a0
	move.w	(a0,d0.w),s_per(a5)
	move.b	#10,s_vol(a5)
	clr.b	s_wave(a5)
	rts

	include	"snd_data.i"
snd_end:
