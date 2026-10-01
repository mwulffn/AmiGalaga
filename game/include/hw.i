; Hardware: custom chip registers as offsets from CUSTOM, their bits, the CIAs.
; Names are Commodore's, in lowercase.

CUSTOM		equ	$dff000

dmaconr		equ	$002
vposr		equ	$004
vhposr		equ	$006
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

CIAA_PRA	equ	$bfe001
CIAAB_FIRE0	equ	6		; left mouse button, active low

PAL_LINES	equ	313
