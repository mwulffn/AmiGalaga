; Graphics data, built from the user's ROM by tools/make_gfx.py.

	xdef	Enemies
	xdef	Font
	xdef	Beam
	xdef	Badges

	section	chip_data,data_c

; 16x16 images for the blitter, FRAME_SIZE bytes each: 16 rows of 4 plane
; words, then the mask in the same layout. A kind of enemy starts at its GFX_
; name in gfx.i and has its 8 frames four times: plain, then flipped top to
; bottom, left to right, and both, FLIP_SIZE apart.
Enemies:	incbin	"enemies.bin"

; the tractor beam: three colour sets of 48 x 80, each line 4 planes of 3 words
Beam:	incbin	"beam.bin"

	section	data,data

; 8x8 glyphs for ASCII 32 to 90, one byte a row
Font:	incbin	"font.bin"

; the stage badge tiles, 8 rows of 4 plane bytes each: 1, 5 (a tile above a tile),
; 10, 20, 30, 50 (two such columns)
Badges:	incbin	"badges.bin"
	even
