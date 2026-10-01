; Hardware: custom chip registers as offsets from CUSTOM, their bits, the CIAs.
; Names are Commodore's, in lowercase.

CUSTOM		equ	$dff000

dmaconr		equ	$002
vposr		equ	$004
vhposr		equ	$006
joy1dat		equ	$00c
intenar		equ	$01c
intreqr		equ	$01e
bltcon0		equ	$040
bltcon1		equ	$042
bltafwm		equ	$044
bltalwm		equ	$046
bltcpt		equ	$048
bltbpt		equ	$04c
bltapt		equ	$050
bltdpt		equ	$054
bltsize		equ	$058
bltcmod		equ	$060
bltbmod		equ	$062
bltamod		equ	$064
bltdmod		equ	$066
cop1lc		equ	$080
cop2lc		equ	$084
copjmp1		equ	$088
copjmp2		equ	$08a
diwstrt		equ	$08e
diwstop		equ	$090
ddfstrt		equ	$092
ddfstop		equ	$094
dmacon		equ	$096
intena		equ	$09a
intreq		equ	$09c
aud0lc		equ	$0a0
bplpt		equ	$0e0
bplcon0		equ	$100
bplcon1		equ	$102
bplcon2		equ	$104
bpl1mod		equ	$108
bpl2mod		equ	$10a
sprpt		equ	$120
spr7pos		equ	$178
spr7ctl		equ	$17a
spr7data	equ	$17c
spr7datb	equ	$17e
color		equ	$180

; dmacon / dmaconr
DMA_SET		equ	$8000
DMA_BLTPRI	equ	$0400
DMA_MASTER	equ	$0200
DMA_BITPLANE	equ	$0100
DMA_COPPER	equ	$0080
DMA_BLITTER	equ	$0040
DMA_SPRITE	equ	$0020
DMA_AUDIO	equ	$000f
DMA_ALL		equ	$7fff
DMAB_BLTBUSY	equ	6		; bit in the high byte of dmaconr

; intena / intreq
INT_SET		equ	$8000
INT_MASTER	equ	$4000
INT_EXTER	equ	$2000		; level 6: CIA-B
INT_BLIT	equ	$0040
INT_VERTB	equ	$0020
INT_ALL		equ	$7fff

; autovectors
VEC_LEVEL1	equ	$64
VEC_LEVEL3	equ	$6c		; vertical blank, blitter, copper
VEC_LEVEL6	equ	$78		; CIA-B
VEC_COUNT	equ	7

; Paula: one block per channel, AUD_SIZE apart
aud_lc		equ	0		; sample address
aud_len		equ	4		; length in words
aud_per		equ	6		; period
aud_vol		equ	8		; volume 0-64
AUD_SIZE	equ	$10
AUD_CHANNELS	equ	4
AUD_MAX_VOLUME	equ	64
PAULA_CLOCK	equ	3546895		; PAL: sample rate = PAULA_CLOCK / period

; CIA-B timer A, on level 6
CIAB_TALO	equ	$bfd400
CIAB_TAHI	equ	$bfd500
CIAB_ICR	equ	$bfdd00
CIAB_CRA	equ	$bfde00
CIA_ICR_SET	equ	$80
CIA_ICR_TA	equ	$01
CIA_ICR_ALL	equ	$7f
CIA_CRA_RUN	equ	$11		; load the latch and run continuously
CIA_E_CLOCK	equ	709379		; PAL: timer ticks per second

CIAA_PRA	equ	$bfe001
CIAA_SDR	equ	$bfec01		; the keyboard's serial data
CIAA_ICR	equ	$bfed01
CIAA_CRA	equ	$bfee01
CIA_ICR_SP	equ	3		; ICR bit: a byte has come in on the serial line
CIA_CRA_SPOUT	equ	6		; CRA bit: the serial line is an output
CIAAB_FIRE0	equ	6		; left mouse button, active low
CIAAB_FIRE1	equ	7		; the joystick's fire button, active low
; joy1dat
JOYB_RIGHT	equ	1
JOYB_LEFT	equ	9

PAL_LINES	equ	313
