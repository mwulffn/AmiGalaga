; Graphics data, built from the user's ROM by tools/make_gfx.py.

	xdef	Enemies
	xdef	Font
	xdef	SpriteImages

	section	chip_data,data_c

; 16x16 images for the blitter, FRAME_SIZE bytes each: 16 rows of 4 plane
; words, then the mask in the same layout. Offsets are the GFX_ names in gfx.i.
Enemies:	incbin	"enemies.bin"

; 16-line images for hardware sprites: two words a line. Offsets are the SPR_ names.
SpriteImages:	incbin	"sprites.bin"

	section	data,data

; 8x8 glyphs for ASCII 32 to 90, one byte a row
Font:	incbin	"font.bin"
