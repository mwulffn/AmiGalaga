; Sound: the arcade's sound driver on Paula.
;
; A port of sound/native.py, which is tick-for-tick identical to the
; arcade's driver. A CIA timer calls SoundTick 121 times a second, as in
; the arcade. Each tick the three voices start silent, the sounds that
; are playing are advanced in a fixed order (later ones overwrite the
; voices of earlier ones), and the result goes to Paula channels 0-2 as a
; period, a volume and one of the arcade's eight waveforms. Channel 3
; plays the fighter's explosion: a noise loop with a decaying volume.
;
; How the game asks for a sound is in sound.i.

	include	"config.i"
	include	"hw.i"
	include	"sound.i"
	include	"state.i"

	xdef	SoundInit
	xdef	SoundStop
	xref	State
	if	SOUND_TEST
	xdef	SoundLog
	endc

TICK_RATE	equ	121			; driver ticks a second, as in the arcade
TICK_PERIOD	equ	CIA_E_CLOCK/TICK_RATE	; timer counts per tick (121.2 a second)

VOICES		equ	3
IDLE_PERIOD	equ	400			; any period: a channel that is silent
WAVE_LONGEST	equ	32			; samples in the longest copy of a waveform
WAVES		equ	8
LENGTH_SHIFT	equ	12			; a period entry holds the length code above the period
PERIOD_MASK	equ	$0fff

NOISE_LENGTH	equ	4000			; bytes in the noise loop
NOISE_PERIOD	equ	PAULA_CLOCK/8000	; it is played at 8 kHz
BANG_TICKS	equ	324			; the explosion lasts 2.67 s
BANG_HOLD	equ	27			; at full level for the first 0.22 s
BANG_DECAY	equ	64833			; then x 0.98927 a tick: it halves every 0.53 s

NOTE_END	equ	$ff			; ends a track
NOTE_REST	equ	$0c
ENV_REST	equ	$ff			; trk_env for a rest
ATTACK_TICKS	equ	6			; envelopes 1 and 2 shape the first ticks of a note
STEADY_VOLUME	equ	10
PULSE_STEP_TICKS equ	$22			; ticks between the pulse's rate changes
PULSE_CLOSING	equ	16			; offset of the closing half of SndPulse
PULSE_PITCH	equ	$20			; from a slide rate to its start pitch
BEAM_TICKS	equ	6
BEAM_TOP	equ	$0c
BEAM_BOTTOM	equ	4
CAPTURE_TICKS	equ	$1c
RESULTS_VOLUME1	equ	9
RESULTS_VOLUME2	equ	6

; how a sound's request byte works
MODE_TRIGGER	equ	0			; starts when set, then runs by itself
MODE_COUNT	equ	1			; a count of plays
MODE_HELD	equ	2			; plays while set

; Handle one sound if it is requested or playing: \1 = its number, \2 = its mode.
; Uses a4 = sound state. One that is neither costs a test and a branch.
SOUND	macro
	tst.w	2*\1(a4)
	beq	.s\@
	moveq	#\1,d7
	moveq	#\2,d6
	lea	2*\1(a4),a3
	bsr	Handle
.s\@
	endm

	section	code,code

;--
; SoundInit
; Silence Paula, start its four channels and the timer that drives the sound.
; In:       a5 = state, a6 = CUSTOM
; Out:      -
; Clobbers: d0, a0
SoundInit:
	lea	Sound(a5),a0
	move.w	#snd_SIZEOF/2-1,d0
.Clear	clr.w	(a0)+
	dbf	d0,.Clear
	if	SOUND_TEST
	move.l	#SoundScript,Sound+snd_script(a5)
	move.l	#SoundLog,Sound+snd_log(a5)
	endc

	lea	aud0lc(a6),a0
	moveq	#VOICES-1,d0
.Voice	move.l	#SndWaves,aud_lc(a0)
	move.w	#WAVE_LONGEST/2,aud_len(a0)
	move.w	#IDLE_PERIOD,aud_per(a0)
	clr.w	aud_vol(a0)
	lea	AUD_SIZE(a0),a0
	dbf	d0,.Voice
	move.l	#SndNoise,aud_lc(a0)
	move.w	#NOISE_LENGTH/2,aud_len(a0)
	move.w	#NOISE_PERIOD,aud_per(a0)
	clr.w	aud_vol(a0)
	move.w	#DMA_SET|DMA_AUDIO,dmacon(a6)

	lea	SoundInterrupt(pc),a0
	move.l	a0,VEC_LEVEL6.w
	move.b	#CIA_ICR_ALL,CIAB_ICR		; no CIA-B interrupts but ours
	move.b	#TICK_PERIOD&$ff,CIAB_TALO
	move.b	#TICK_PERIOD>>8,CIAB_TAHI
	move.b	#CIA_ICR_SET|CIA_ICR_TA,CIAB_ICR
	move.b	#CIA_CRA_RUN,CIAB_CRA
	move.w	#INT_EXTER,intreq(a6)
	move.w	#INT_SET|INT_EXTER,intena(a6)
	rts

;--
; SoundStop
; Stop the timer and silence Paula.
; In:       a6 = CUSTOM
; Out:      -
; Clobbers: d0, a0
SoundStop:
	move.w	#INT_EXTER,intena(a6)
	clr.b	CIAB_CRA
	move.b	#CIA_ICR_TA,CIAB_ICR
	lea	aud0lc(a6),a0
	moveq	#AUD_CHANNELS-1,d0
.Mute	clr.w	aud_vol(a0)
	lea	AUD_SIZE(a0),a0
	dbf	d0,.Mute
	move.w	#DMA_AUDIO,dmacon(a6)
	rts

;--
; SoundInterrupt
; Level 6 interrupt: the CIA timer. One driver tick.
; lint: allow a5, a6
; In:       -
; Out:      -
; Clobbers: -
SoundInterrupt:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	State,a5
	lea	CUSTOM,a6
	lea	Sound(a5),a4
	tst.b	CIAB_ICR			; reading it acknowledges the timer

	if	SOUND_TEST
	; apply this tick's script entries: tick, offset in the sound state, value
	move.w	snd_ticks(a4),d0
	move.l	snd_script(a4),a0
.Event	cmp.w	(a0),d0
	bne	.Scripted
	moveq	#0,d1
	move.b	2(a0),d1
	move.b	3(a0),(a4,d1.w)
	addq.l	#4,a0
	bra	.Event
.Scripted
	move.l	a0,snd_script(a4)
	endc

	bsr	SoundTick

	if	SOUND_TEST
	; log what this tick sent to the three voices: periods, volumes, waveforms
	cmp.w	#SOUND_TEST,snd_ticks(a4)
	bcc	.Logged
	addq.w	#1,snd_ticks(a4)
	move.l	snd_log(a4),a0
	move.w	snd_per(a4),(a0)+
	move.w	snd_per+2(a4),(a0)+
	move.w	snd_per+4(a4),(a0)+
	moveq	#VOICES-1,d1
	lea	snd_vol(a4),a1
.LogVolume
	moveq	#15,d0
	and.b	(a1)+,d0
	move.b	d0,(a0)+
	dbf	d1,.LogVolume
	moveq	#VOICES-1,d1
.LogWave
	moveq	#WAVES-1,d0
	and.b	(a1)+,d0
	move.b	d0,(a0)+
	dbf	d1,.LogWave
	move.l	a0,snd_log(a4)
.Logged
	endc

	move.w	#INT_EXTER,intreq(a6)
	movem.l	(sp)+,d0-d7/a0-a6
	rte

;--
; SoundTick
; Advance every playing sound by one tick and send the result to Paula.
; In:       a4 = sound state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d7, a0-a3
SoundTick:
	lea	snd_trk(a4),a2
	clr.w	snd_vol(a4)			; the voices start silent
	clr.b	snd_vol+2(a4)
	clr.l	snd_per(a4)
	clr.w	snd_per+4(a4)
	tst.b	SND_PULSE(a4)
	beq	.NoPulse
	bsr	FormationPulse
.NoPulse
	; every other sound, in the arcade's order: later ones overwrite earlier ones
	SOUND	$13,MODE_TRIGGER
	SOUND	$0f,MODE_TRIGGER
	SOUND	$03,MODE_TRIGGER
	SOUND	$02,MODE_TRIGGER
	SOUND	$04,MODE_TRIGGER
	SOUND	$01,MODE_TRIGGER
	SOUND	$12,MODE_COUNT
	SOUND	$05,MODE_HELD
	SOUND	$06,MODE_HELD
	SOUND	$09,MODE_HELD
	SOUND	$07,MODE_COUNT
	SOUND	$11,MODE_HELD
	SOUND	$0d,MODE_COUNT
	SOUND	$0e,MODE_COUNT
	SOUND	$14,MODE_COUNT
	SOUND	$15,MODE_COUNT
	SOUND	$0a,MODE_COUNT
	SOUND	$0b,MODE_COUNT
	SOUND	$10,MODE_HELD
	SOUND	$0c,MODE_COUNT
	SOUND	$16,MODE_COUNT
	SOUND	$08,MODE_COUNT
	bra	ToPaula

;--
; Handle
; Start, continue or stop one sound according to its request byte.
; In:       d7 = sound, d6 = its mode, a3 = its request byte (the playing byte follows),
;           a2 = tracks, a4 = sound state
; Out:      -
; Clobbers: d0-d6, a0-a1
Handle:	tst.b	d6
	bne	.Gated
	tst.b	(a3)				; trigger: the request starts it
	beq	.Running
	clr.b	(a3)
	addq.b	#1,1(a3)
	moveq	#1,d5
	bra	Play
.Running
	moveq	#0,d5
	bra	Play
.Gated	tst.b	(a3)				; count and held: plays while requested
	bne	.On
	clr.b	1(a3)
	rts
.On	moveq	#0,d5
	tst.b	1(a3)
	bne	.Go
	move.b	#1,1(a3)
	moveq	#1,d5
.Go	bsr	Play
	beq	.Extras
	subq.b	#MODE_COUNT,d6
	bne	.Extras
	cmp.b	#SND_COIN/2,d7			; a counted sound ended
	beq	.Coin
	cmp.b	#SND_NAME_A/2,d7
	beq	.Name
	clr.b	(a3)
	cmp.b	#SND_PERFECT/2,d7
	bne	.Extras
	move.b	#1,SND_DIVE(a4)			; "perfect" is followed by the dive sound
	bra	.Extras
.Name	subq.b	#1,(a3)				; name entry alternates with its second tune
	beq	.Other
	btst	#0,(a3)
	beq	.Extras
.Other	move.b	#1,SND_NAME_B(a4)
	bra	.Extras
.Coin	subq.b	#1,(a3)				; once per credit
.Extras	cmp.b	#SND_BEAM/2,d7
	beq	.Beam
	cmp.b	#SND_BEAM_CAPTURE/2,d7
	beq	.Capture
	cmp.b	#SND_RESULTS/2,d7
	bne	.Done
	move.b	#RESULTS_VOLUME1,snd_vol+1(a4)	; results tune: fixed volumes
	move.b	#RESULTS_VOLUME2,snd_vol+2(a4)
.Done	rts
.Beam	addq.b	#1,snd_btick(a4)		; tractor beam: voice 2's volume sweeps down and wraps
	cmp.b	#BEAM_TICKS,snd_btick(a4)
	bcs	.BeamVolume
	clr.b	snd_btick(a4)
	move.b	snd_bvol(a4),d0
	cmp.b	#BEAM_BOTTOM,d0
	bcs	.Wrap
	subq.b	#1,d0
	bra	.BeamSet
.Wrap	moveq	#BEAM_TOP,d0
.BeamSet
	move.b	d0,snd_bvol(a4)
.BeamVolume
	move.b	snd_bvol(a4),snd_vol+2(a4)
	rts
.Capture
	addq.b	#1,snd_bwtick(a4)		; capture: voice 0 steps through the waveforms
	cmp.b	#CAPTURE_TICKS,snd_bwtick(a4)
	bne	.CaptureWave
	clr.b	snd_bwtick(a4)
	addq.b	#1,snd_bwave(a4)
.CaptureWave
	move.b	snd_bwave(a4),snd_wave(a4)
	rts

;--
; Play
; Advance every track of one sound by a tick.
; In:       d7 = sound, d5 = nonzero to start from the top, a2 = tracks,
;           a3 = the sound's request byte, a4 = sound state
; Out:      d0 = nonzero if the sound ended, Z = it did not
; Clobbers: d1-d5, a0-a1
Play:	move.w	d7,d0
	add.w	d0,d0
	add.w	d7,d0
	lea	SndParms(pc),a0
	add.w	d0,a0
	moveq	#0,d1
	move.b	(a0)+,d1			; first track
	moveq	#0,d2
	move.b	(a0)+,d2			; tracks
	moveq	#0,d3
	move.b	(a0),d3				; first voice
	cmp.b	#SND_RESULTS/2,d7		; the results tune brings its voices in one at a time
	bne	.Count
	tst.b	RESULTS_TRACK*trk_SIZEOF+trk_pos(a2)
	beq	.One
	cmp.b	#1,RESULTS_TRACK*trk_SIZEOF+trk_pos(a2)
	beq	.Two
	tst.b	(RESULTS_TRACK+1)*trk_SIZEOF+trk_pos(a2)
	bne	.Count
.Two	moveq	#2,d2
	bra	.Count
.One	moveq	#1,d2
.Count	subq.w	#1,d2
	tst.b	d5
	beq	.Track
	move.w	d1,d0
	lsl.w	#3,d0				; * trk_SIZEOF
	lea	(a2,d0.w),a0
	move.w	d2,d0
.Rewind	clr.w	(a0)				; clock and position
	addq.l	#trk_SIZEOF,a0
	dbf	d0,.Rewind
.Track	bsr	Track
	addq.w	#1,d1
	addq.w	#1,d3
	dbf	d2,.Track
	move.b	snd_fin(a4),d0
	beq	.Return
	clr.b	snd_fin(a4)
	clr.b	1(a3)
	moveq	#1,d0
.Return	rts

RESULTS_TRACK	equ	$1c			; the results tune's first track

;--
; Track
; Advance one track by a tick and write its voice.
; In:       d7 = sound, d1 = track, d3 = voice, a2 = tracks, a4 = sound state
; Out:      -
; Clobbers: d0, d4-d5, a0-a1
Track:	move.w	d1,d0
	lsl.w	#3,d0				; * trk_SIZEOF
	lea	(a2,d0.w),a0
	addq.b	#1,trk_clock(a0)
	moveq	#0,d4
	move.b	trk_clock(a0),d4		; ticks into this note
	cmp.b	#1,d4
	bne	.Playing
	move.w	d1,d0				; first tick of a note: look everything up once
	add.w	d0,d0
	lea	SndTrackPtr(pc),a1
	move.w	(a1,d0.w),d0
	lea	SndTracks(pc),a1
	add.w	d0,a1
	move.b	(a1)+,trk_env(a0)		; the track's header
	move.b	(a1)+,trk_delay(a0)
	move.b	(a1)+,trk_wave(a0)
	moveq	#0,d0
	move.b	trk_pos(a0),d0
	add.w	d0,a1				; the (note, length) pair
	moveq	#0,d0
	move.b	(a1)+,d0
	cmp.b	#NOTE_END,d0
	bne	.Note
	clr.b	trk_clock(a0)			; the end: look again next tick
	clr.b	snd_vol(a4,d3.w)
	st	snd_fin(a4)
	rts
.Note	cmp.b	#NOTE_REST,d0
	bne	.Pitch
	st	trk_env(a0)
.Pitch	moveq	#0,d5
	move.b	(a1),d5				; length
	add.w	d0,d0
	lea	SndNotes(pc),a1
	move.w	(a1,d0.w),trk_per(a0)
	moveq	#0,d0
	lea	SndTempo(pc),a1
	move.b	(a1,d7.w),d0
	mulu.w	d5,d0				; ticks = tempo * length, low byte
	move.b	d0,trk_dur(a0)
.Playing
	move.w	d3,d5
	add.w	d5,d5
	move.w	trk_per(a0),snd_per(a4,d5.w)
	move.b	trk_env(a0),d5
	beq	.Steady
	bmi	.Mute
	cmp.b	#ATTACK_TICKS,d4
	bcc	.Steady
	subq.b	#1,d5
	bne	.Sharp
	move.b	d4,d5				; envelope 1: fade in
	add.b	d5,d5
	bra	.Set
.Sharp	move.b	d4,d5				; envelope 2: 14, 13, ... a sharp start
	not.b	d5
	bra	.Set
.Steady	; volume = 10 until the delay has passed, then 10 - (clock - delay), not below 0
	moveq	#STEADY_VOLUME,d5
	moveq	#0,d0
	move.b	trk_delay(a0),d0
	beq	.Set
	sub.w	d4,d0
	bhi	.Set
	add.w	d0,d5
	bpl	.Set
.Mute	moveq	#0,d5
.Set	move.b	d5,snd_vol(a4,d3.w)
	move.b	trk_wave(a0),snd_wave(a4,d3.w)
	cmp.b	trk_dur(a0),d4			; note over?
	bne	.Same
	addq.b	#2,trk_pos(a0)
	clr.b	trk_clock(a0)
.Same	rts

;--
; FormationPulse
; The formation's pulse: voice 0 slides up while the formation opens, down while it closes.
; In:       a2 = tracks, a4 = sound state
; Out:      -
; Clobbers: d0-d1, a0
FormationPulse:
	move.b	snd_dir(a4),d0
	cmp.b	snd_pdir(a4),d0
	beq	.Same
	move.b	d0,snd_pdir(a4)
	moveq	#0,d1
	addq.b	#1,d0				; $ff: closing
	bne	.Open
	moveq	#PULSE_CLOSING,d1
.Open	move.w	d1,snd_ptab(a4)
	clr.b	trk_clock(a2)			; track 0's clock is the pulse's own
	clr.b	snd_pstep(a4)
	bra	.Load
.Same	addq.b	#1,trk_clock(a2)
	cmp.b	#PULSE_STEP_TICKS,trk_clock(a2)
	bne	.Slide
	clr.b	trk_clock(a2)
	addq.b	#1,snd_pstep(a4)
.Load	moveq	#0,d0
	move.b	snd_pstep(a4),d0
	add.w	d0,d0
	add.w	snd_ptab(a4),d0
	lea	SndPulse(pc),a0
	add.w	d0,a0
	move.w	(a0),snd_prate(a4)
	move.w	PULSE_PITCH(a0),snd_ppitch(a4)
.Slide	move.w	snd_ppitch(a4),d0
	add.w	snd_prate(a4),d0
	move.w	d0,snd_ppitch(a4)
	lsr.w	#8,d0
	add.w	d0,d0
	lea	SndPulsePeriod(pc),a0
	move.w	(a0,d0.w),snd_per(a4)
	move.b	#STEADY_VOLUME,snd_vol(a4)
	clr.b	snd_wave(a4)
	rts

; Paula volume for the arcade's 16 levels. The explosion plays at 64; in
; the arcade it is about 10 dB louder than the start theme, and tones at
; 1.5 x level leave it about 10.7 dB louder here.
ToneVolume:	dc.b	0,2,3,5,6,8,9,11,12,14,15,17,18,20,21,23
; where each length of waveform copy starts in SndWaves: 32, 16, 8 samples
WaveBase:	dc.w	0,WAVES*32,WAVES*32+WAVES*16

;--
; ToPaula
; Write the three voices and the explosion to Paula.
; In:       a4 = sound state, a6 = CUSTOM
; Out:      -
; Clobbers: d0-d4, d6, a0-a3
ToPaula:
	move.b	snd_vol(a4),d0
	or.b	snd_vol+1(a4),d0
	or.b	snd_vol+2(a4),d0
	bne	.Send
	tst.b	snd_quiet(a4)			; silent, and Paula has been told
	bne	.Explosion
.Send	tst.b	d0
	seq	snd_quiet(a4)
	lea	aud0lc(a6),a0
	lea	snd_per(a4),a1
	lea	snd_last(a4),a3
	moveq	#0,d6				; voice
.Voice	moveq	#15,d0
	and.b	snd_vol(a4,d6.w),d0
	move.w	(a1)+,d1
	bne	.Sounding
	moveq	#0,d0
.Sounding
	move.b	ToneVolume(pc,d0.w),d0
	move.w	d0,aud_vol(a0)
	beq	.Next
	moveq	#WAVES-1,d3
	and.b	snd_wave(a4,d6.w),d3
	cmp.w	(a3),d1				; same note and waveform as last time?
	bne	.Change
	cmp.b	2(a3),d3
	beq	.Next
.Change	move.w	d1,(a3)
	move.b	d3,2(a3)
	move.w	d1,d2
	and.w	#PERIOD_MASK,d2
	move.w	d2,aud_per(a0)
	rol.w	#16-LENGTH_SHIFT,d1
	and.w	#3,d1				; length code: 32, 16, 8 samples
	; address = SndWaves + WaveBase[code] + waveform * (32 >> code)
	moveq	#5,d4
	sub.w	d1,d4
	lsl.w	d4,d3
	move.w	d1,d4
	add.w	d4,d4
	add.w	WaveBase(pc,d4.w),d3
	lea	SndWaves,a2
	add.w	d3,a2
	move.l	a2,aud_lc(a0)			; Paula picks these up when the current pass ends
	moveq	#WAVE_LONGEST/2,d4
	lsr.w	d1,d4
	move.w	d4,aud_len(a0)
.Next	lea	AUD_SIZE(a0),a0
	addq.l	#4,a3
	addq.w	#1,d6
	cmp.w	#VOICES,d6
	bne	.Voice

.Explosion
	lea	aud0lc+VOICES*AUD_SIZE(a6),a0
	tst.b	snd_bang(a4)			; full level, then a steady halving
	beq	.NoBang
	clr.b	snd_bang(a4)
	move.w	#$ffff,snd_gain(a4)
	move.w	#BANG_TICKS,snd_left(a4)
.NoBang	moveq	#0,d1
	move.w	snd_left(a4),d0
	beq	.Noise
	subq.w	#1,d0
	move.w	d0,snd_left(a4)
	move.w	snd_gain(a4),d1
	cmp.w	#BANG_TICKS-BANG_HOLD,d0
	bcc	.Level
	mulu.w	#BANG_DECAY,d1
	swap	d1
	move.w	d1,snd_gain(a4)
.Level	lsr.w	#8,d1				; the top 6 bits of the level, as volume 1-64
	lsr.w	#2,d1
	addq.w	#1,d1
.Noise	move.w	d1,aud_vol(a0)
	rts

	include	"snd_data.i"

	if	SOUND_TEST
SoundScript:
	include	"sndtest_script.i"

	section	bss,bss
SoundLog:	ds.b	SOUND_TEST*SOUND_LOG_ENTRY
	endc

	section	chip_data,data_c

; the 8 waveforms in lengths 32, 16 and 8, then the noise loop
SndWaves:	incbin	"snd_chip.bin",0,WAVES*(32+16+8)
SndNoise:	incbin	"snd_chip.bin",WAVES*(32+16+8),NOISE_LENGTH
