; Flight: an enemy flying a script. See flight.s.

FLIGHT_SLOTS	equ	12		; as many as the arcade flies at once

; An enemy is known by its object number, as in the arcade: even numbers,
; $08-$2e the 20 bees, $30-$36 the 4 bosses, $38-$3e enemies that only fly
; through, $40-$5e the 16 butterflies, $00-$06 captured fighters.
OBJECTS		equ	$80
STAGE_WAVES	equ	5			; a stage's enemies arrive in 5 waves of 8
WAVE_BYTES	equ	STAGE_WAVES*(1+2*8)+1		; a start mark and 8 (control, object) pairs each, an end mark

; Time is counted in fifths of an arcade frame. A displayed frame uses up
; FIFTHS of them: 6 on a 50 Hz display, which keeps the arcade's speed;
; 5 reproduces the arcade exactly and is the build that is checked against it.
FIFTHS		equ	6-EXACT_TIMING
FRAME_FIFTHS	equ	5		; fifths in one arcade frame

; what FlightStep returns
FLIGHT_FLYING	equ	0
FLIGHT_HOME	equ	1		; reached its place in the formation
FLIGHT_GONE	equ	2		; its script ended

; a STAGE_TEST build logs these two, launches, and a checksum of the formation's table each frame
STAGE_LAUNCHED	equ	0
STAGE_FORMATION	equ	3
STAGE_LOG_BYTES	equ	4*4096

; fl_flags bits
FLB_ACTIVE	equ	0
FLB_PAUSE	equ	1		; standing still for one arcade frame
FLB_DIVING	equ	2		; watching for its dive depth
FLB_HOMING	equ	3		; heading for its place in the formation
FLB_LANDED	equ	4		; home, and drawn there until its row's strip is next rebuilt
FLB_MIRROR	equ	7		; flies the script mirrored

; Positions are in the arcade's own space, 1/128 pixel: x from the left,
; y from the bottom. On the 224 x 288 arcade screen the sprite's left edge
; is x/128 - 17 and its top edge is 312 - y/128; a homing enemy is drawn
; fl_xo to the right and fl_yo lower.
	rsreset
fl_y		rs.w	1
fl_x		rs.w	1
fl_head		rs.l	1		; heading: 2^32 is a full turn, 0 is right, a quarter is up
fl_turn		rs.l	1		; heading added per displayed frame within a step
fl_dist		rs.w	2		; distance per displayed frame: even frames, odd frames
fl_script	rs.w	1		; next token, as an offset into MotionScripts
fl_left		rs.w	1		; fifths left in the current step
fl_rate		rs.b	1		; the step's turn rate, mirrored if the flight is
fl_lo		rs.b	1		; the step's two speeds: odd frames,
fl_hi		rs.b	1		;   even frames
fl_flags	rs.b	1
fl_ty		rs.b	1		; target: home (y, x in two-pixel units), or dive depth
fl_tx		rs.b	1
fl_yo		rs.b	1		; while homing: the formation's offset when it turned for home
fl_xo		rs.b	1
fl_obj		rs.b	1		; which enemy this is: selects its place in the formation
fl_pad		rs.b	1
fl_SIZEOF	rs.b	0
