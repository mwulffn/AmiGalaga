; Sound: how the game asks for sounds, and the driver's state.
;
; To request sound n, write to its request byte: a count of plays, or
; on/off for the held sounds. From game code, with a5 = state:
;
;	move.b	#1,Sound+SND_SHOT(a5)
;
; Also snd_dir for the way the formation is moving ($ff closing, anything
; else opening; the pulse follows it) and snd_bang for the fighter's
; explosion.

SND_PULSE	equ	2*$00		; held: the formation's pulse
SND_HIT_BOSS2	equ	2*$01
SND_HIT_BUTTERFLY equ	2*$02
SND_HIT_BEE	equ	2*$03
SND_HIT_BOSS1	equ	2*$04
SND_BEAM	equ	2*$05		; held: tractor beam
SND_BEAM_CAPTURE equ	2*$06		; held
SND_FIGHTER_LOST equ	2*$07
SND_COIN	equ	2*$08
SND_CAPTURED	equ	2*$09		; held: fighter captured
SND_EXTRA_FIGHTER equ	2*$0a
SND_START	equ	2*$0b		; the start theme
SND_NAME_A	equ	2*$0c
SND_CHALLENGE	equ	2*$0d
SND_RESULTS	equ	2*$0e
SND_SHOT	equ	2*$0f
SND_NAME_LOOP	equ	2*$10		; held
SND_RESCUED	equ	2*$11		; held
SND_TRANSFORM	equ	2*$12
SND_DIVE	equ	2*$13
SND_PERFECT	equ	2*$14
SND_BADGE	equ	2*$15
SND_NAME_B	equ	2*$16

SND_TRACKS	equ	48
SOUND_LOG_ENTRY	equ	12		; test: bytes logged per tick

; one track of a sound
	rsreset
trk_clock	rs.b	1		; ticks into the current note
trk_pos		rs.b	1		; offset of the current (note, length) pair
trk_env		rs.b	1		; envelope type from the track's header; $ff for a rest
trk_delay	rs.b	1		; envelope delay from the header
trk_wave	rs.b	1		; waveform from the header
trk_dur		rs.b	1		; ticks this note lasts
trk_per		rs.w	1		; its Paula period | waveform length code << 12
trk_SIZEOF	rs.b	0

; the driver's state: the Sound field of the game state
	rsreset
snd_req		rs.b	64		; per sound: a request byte the game writes,
					; then a byte that is set while it plays
snd_vol		rs.b	3		; the three voices this tick
snd_wave	rs.b	3		; kept between ticks
snd_fin		rs.b	1		; a track reached its end this tick
snd_dir		rs.b	1		; formation direction, written by the game
snd_bang	rs.b	1		; explosion request, written by the game
snd_pdir	rs.b	1		; pulse: the direction last seen
snd_pstep	rs.b	1
snd_bvol	rs.b	1		; tractor beam: voice 2's volume and its timer
snd_btick	rs.b	1
snd_bwave	rs.b	1		; capture: voice 0's waveform and its timer
snd_bwtick	rs.b	1
snd_quiet	rs.b	1		; the three voices were silent last tick
snd_per		rs.w	3		; Paula period | length code << 12, per voice
snd_ptab	rs.w	1		; pulse: 0 opening, 16 closing
snd_prate	rs.w	1
snd_ppitch	rs.w	1
snd_gain	rs.w	1		; explosion: level, ticks left
snd_left	rs.w	1
snd_last	rs.b	12		; per voice: period entry and waveform last sent to Paula
	if	SOUND_TEST
snd_ticks	rs.w	1		; test: ticks so far
snd_script	rs.l	1		;   next script entry
snd_log		rs.l	1		;   next log entry
	endc
snd_trk		rs.b	SND_TRACKS*trk_SIZEOF
snd_SIZEOF	rs.b	0
