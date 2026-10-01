"""Build the game's graphics from the user's ROM set.

    python3 make_gfx.py path/to/galaga.zip build

Extract Galaga's enemy sprites to Amiga interleaved bitplanes.

Reads the arcade ROM zip and writes:
  enemies.bin  one 256-byte record per image: 16 rows x 4 planes x 1 word of
               image data (row-interleaved), then the same layout for the mask.
               Every kind of enemy has 32 images: its 8 frames (six turned in
               15 degree steps from pointing left, then upright with wings
               open and closed) four times over: as they are, flipped top to
               bottom, flipped left to right, and both. That is how the
               arcade's sprite hardware gets all 24 directions from them.
               After the enemies come the explosion's images and the score
               pop-ups, one image each.
  sprites.bin  fighter + bullet as 2-plane hardware sprite image words
  font.bin     1-bit 8x8 glyphs for ASCII 32..90 (space, digits, A-Z)
  badges.bin   the stage badge tiles: 8 rows of 4 plane bytes each
  beam.bin     the tractor beam in its three colour sets, 48x80 each
  gfx.i        vasm include with frame offsets and the palettes
  sheet.png    contact sheet for eyeballing (optional, needs pillow)
"""

import sys
import zipfile
from pathlib import Path

# 16-colour playfield palette (OCS $RGB): black + the 15 colours measured in MAME.
PALETTE = [
    0x000, 0xDDF, 0xF00, 0xFF0, 0x06F, 0x0FF, 0xF0F, 0x0F0,
    0xD40, 0x09A, 0x90F, 0x00F, 0xFB0, 0xF90, 0x0BF, 0xB0F,
]  # fmt: skip

# (name, colour code, first tile, frame count) - pairs observed in the MAME trace.
ENEMIES = [
    ("boss", 0, 0x08, 8),
    ("bosshit", 1, 0x08, 8),
    ("butterfly", 2, 0x10, 8),
    ("bee", 3, 0x18, 8),
    ("scorpion", 4, 0x50, 7),
    ("bosconian", 5, 0x58, 7),
    ("galaxian", 6, 0x60, 7),
    ("dragonfly", 2, 0x68, 7),
    ("satellite", 2, 0x70, 7),
    ("enterprise", 2, 0x78, 7),
    ("fighter", 9, 0x00, 8),  # in playfield colours, for the lives icons
]
# Explosion: three 16x16 frames, then two 32x32 ones as four tiles each (the arcade doubles the
# sprite: tile n is top right, n+1 bottom right, n+2 top left, n+3 bottom left on the upright
# screen), listed here top left, top right, bottom left, bottom right.
BLAST = [(t, 10) for t in (0x41, 0x42, 0x43, 0x46, 0x44, 0x47, 0x45, 0x4A, 0x48, 0x4B, 0x49)]
# Score pop-ups for a boss shot while diving: 400, 800, 1600; and for all eight of a
# challenging stage's wave: 1000, 1500.
POINTS = [(0x35, 10), (0x37, 13), (0x3A, 14), (0x38, 13), (0x39, 13)]
BOMB = (0x30, 11)  # the fighter's bullet, upside down in another colour set
# The fighter's explosion: four 32x32 frames in colour set 11, shown on hardware sprites 0 and 1
# (left and right halves). Their colour registers hold the fighter's colours, so each of the
# explosion's colours is given the pen whose register has it; its cyan takes the place of the
# fighter's blue, which the game swaps in the copper list while the explosion shows.
BANG = (0x20, 0x24, 0x28, 0x2C)
BANG_PENS = {0xDDF: 3, 0xF00: 1, 0x0FF: 2}
FIGHTER = (9, 0x06)  # colour code, tile
BULLET = (9, 0x30)

W3, W2 = (0x21, 0x47, 0x97), (0x51, 0xAE)


def ocs(v: int) -> int:
    """Palette PROM byte -> 12-bit Amiga colour."""
    r = sum(W3[i] for i in range(3) if v >> i & 1)
    g = sum(W3[i] for i in range(3) if v >> (3 + i) & 1)
    b = sum(W2[i] for i in range(2) if v >> (6 + i) & 1)
    return round(r / 17) << 8 | round(g / 17) << 4 | round(b / 17)


def tile_pens(rom: bytes, tile: int) -> list[list[int]]:
    """Decode a 16x16 2bpp sprite tile, rotated to the upright cabinet view."""
    raster = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            byte = rom[tile * 64 + (y if y < 8 else 24 + y) + (x // 4) * 8]
            bit = x % 4
            raster[y][x] = (byte >> (7 - bit) & 1) << 1 | (byte >> (3 - bit) & 1)
    # MAME ROT90: screen(x, y) = raster(y, 15 - x)
    return [[raster[15 - x][y] for x in range(16)] for y in range(16)]


def char_bits(rom: bytes, code: int) -> bytes:
    """Decode an 8x8 character to 1 bit per pixel, upright, one byte per row."""
    raster = [[0] * 8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            byte = rom[code * 16 + y + (8 if x < 4 else 0)]
            bit = x % 4
            raster[y][x] = (byte >> (7 - bit) & 1) | (byte >> (3 - bit) & 1)
    rows = [[raster[7 - x][y] for x in range(8)] for y in range(8)]
    return bytes(sum(b << (7 - x) for x, b in enumerate(row)) for row in rows)


def font(rom: bytes) -> bytes:
    """Glyphs for ASCII 32..90; Galaga has 0-9 at $00, A-Z at $0a, space at $24."""
    out = bytearray()
    for c in range(32, 91):
        ch = chr(c)
        code = int(ch) if ch.isdigit() else ord(ch) - 55 if ch.isalpha() else 0x24
        out += char_bits(rom, code)
    return bytes(out)


BADGE_TILES = range(0x36, 0x4A)  # stage badges: 1, 5 (a column each), 10, 20, 30, 50 (two columns)


def badges(rom: bytes, lut: bytes, pal: bytes) -> bytes:
    """The stage badge tiles in the playfield palette: 8 rows of 4 plane bytes each."""
    out = bytearray()
    for tile in BADGE_TILES:
        code = 1 if tile < 0x3A or tile >= 0x46 else 2  # the arcade's colour set for the tile
        raster = [[0] * 8 for _ in range(8)]
        for y in range(8):
            for x in range(8):
                byte = rom[tile * 16 + y + (8 if x < 4 else 0)]
                raster[y][x] = (byte >> (7 - x % 4) & 1) << 1 | (byte >> (3 - x % 4) & 1)
        for y in range(8):
            row = [PALETTE.index(ocs(pal[(lut[code * 4 + raster[7 - x][y]] & 15) | 0x10])) for x in range(8)]
            out += bytes(sum(1 << (7 - x) for x in range(8) if row[x] >> plane & 1) for plane in range(4))
    return bytes(out)


# The tractor beam: 10 rows of 6 character tiles, narrow at the top, in the arcade's three
# colour sets for it, which it cycles through.
BEAM_ROWS = [[0x24, t, t + 1, t + 2, t + 3, 0x24] for t in range(0x4E, 0x62, 4)] + [
    list(range(t, t + 6)) for t in range(0x62, 0x80, 6)
]
BEAM_SETS = (0x18, 0x19, 0x1A)


def beam(rom: bytes, lut: bytes, pal: bytes) -> bytes:
    """Three 48x80 images, interleaved: per line, 4 planes of 3 words."""
    out = bytearray()
    for code in BEAM_SETS:
        for tiles in BEAM_ROWS:
            pens = []
            for tile in tiles:
                raster = [[0] * 8 for _ in range(8)]
                for y in range(8):
                    for x in range(8):
                        byte = rom[tile * 16 + y + (8 if x < 4 else 0)]
                        raster[y][x] = (byte >> (7 - x % 4) & 1) << 1 | (byte >> (3 - x % 4) & 1)
                pens.append([[raster[7 - x][y] for x in range(8)] for y in range(8)])
            for y in range(8):
                row = [PALETTE.index(ocs(pal[(lut[code * 4 + p] & 15) | 0x10])) for t in pens for p in t[y]]
                for plane in range(4):
                    out += sum(1 << (47 - x) for x in range(48) if row[x] >> plane & 1).to_bytes(6, "big")
    return bytes(out)


def main() -> None:
    zip_path, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        rom = z.read("gg1_11.4d") + z.read("gg1_10.4f")
        pal, lut = z.read("prom-5.5n"), z.read("prom-3.1c")
        char_rom, char_lut = z.read("gg1_9.4l"), z.read("prom-4.2n")
        (out / "font.bin").write_bytes(font(char_rom))
        pal = z.read("prom-5.5n")
        (out / "badges.bin").write_bytes(badges(char_rom, char_lut, pal))

    def colours(code: int) -> list[int | None]:
        """Pen -> OCS colour, None where transparent."""
        idx = [lut[code * 4 + p] & 15 for p in range(4)]
        return [None if i == 15 else ocs(pal[i]) for i in idx]

    frames = bytearray()
    sheet = []
    inc = [
        "; generated by tools/make_gfx.py from the user's ROM - do not edit, do not commit",
        "FRAME_SIZE\tequ\t256",
        "FLIP_SIZE\tequ\t8*FRAME_SIZE\t; from an image to the same frame flipped: x1 top to bottom, x2 left to right",
        "KIND_SHIFT\tequ\t13\t; a kind of enemy is 32 images",
    ]
    for kind, (name, code, first, count) in enumerate(ENEMIES):
        inc.append(f"KIND_{name.upper()}\tequ\t{kind}")
        inc.append(f"GFX_{name.upper()}\tequ\t{len(frames)}")
        cols = colours(code)
        tiles = list(range(first, first + count)) + [first + count - 1] * (8 - count)  # no wings-closed frame: repeat
        for flip in range(4):
            for t in tiles:
                pens = tile_pens(rom, t)
                pix = [[0 if cols[p] is None else PALETTE.index(cols[p]) for p in r] for r in pens]
                if flip & 1:
                    pix = pix[::-1]
                if flip & 2:
                    pix = [r[::-1] for r in pix]
                if not flip:
                    sheet.append(pix)
                data, mask = bytearray(), bytearray()
                for row in pix:
                    m = sum(1 << (15 - x) for x in range(16) if row[x])
                    for plane in range(4):
                        w = sum(1 << (15 - x) for x in range(16) if row[x] >> plane & 1)
                        data += w.to_bytes(2, "big")
                        mask += m.to_bytes(2, "big")
                frames += data + mask
    for label, tiles in (("BLAST", BLAST), ("POINTS", POINTS), ("BOMB", [BOMB])):
        inc.append(f"GFX_{label}\tequ\t{len(frames)}")
        for t, code in tiles:
            cols = colours(code)
            pix = [[0 if cols[p] is None else PALETTE.index(cols[p]) for p in r] for r in tile_pens(rom, t)]
            if label == "BOMB":
                pix = pix[::-1]
            sheet.append(pix)
            for row in pix:
                m = sum(1 << (15 - x) for x in range(16) if row[x])
                frames += b"".join(
                    sum(1 << (15 - x) for x in range(16) if row[x] >> plane & 1).to_bytes(2, "big") for plane in range(4)
                )
            for row in pix:
                frames += sum(1 << (15 - x) for x in range(16) if row[x]).to_bytes(2, "big") * 4
    (out / "enemies.bin").write_bytes(frames)

    spr = bytearray()
    for label, (code, tile) in (("FIGHTER", FIGHTER), ("BULLET", BULLET)):
        inc.append(f"SPR_{label}\tequ\t{len(spr)}")
        for row in tile_pens(rom, tile):
            for plane in range(2):
                w = sum(1 << (15 - x) for x in range(16) if row[x] >> plane & 1)
                spr += w.to_bytes(2, "big")
    inc.append(f"SPR_BANG\tequ\t{len(spr)}\t; 4 frames x left half, right half x 32 lines")
    cols = colours(11)
    for tile in BANG:
        # tile n is top right, n+1 bottom right, n+2 top left, n+3 bottom left on the upright screen
        for top, bottom in ((tile + 2, tile + 3), (tile, tile + 1)):
            for row in tile_pens(rom, top) + tile_pens(rom, bottom):
                pens = [0 if cols[p] is None else BANG_PENS[cols[p]] for p in row]
                for plane in range(2):
                    spr += sum(1 << (15 - x) for x in range(16) if pens[x] >> plane & 1).to_bytes(2, "big")
    # the fighter in every direction, for when it spins in the tractor beam and for the captured
    # (red) fighter flying: 8 frames x 4 flips as the enemies have them; the captured fighter
    # uses the same pens with sprite 4's colour registers
    inc.append(f"SPR_SPIN\tequ\t{len(spr)}\t; 4 flips x 8 frames x 16 lines")
    for flip in range(4):
        for tile in range(8):
            rows = tile_pens(rom, tile)
            if flip & 1:
                rows = rows[::-1]
            if flip & 2:
                rows = [r[::-1] for r in rows]
            for row in rows:
                for plane in range(2):
                    spr += sum(1 << (15 - x) for x in range(16) if row[x] >> plane & 1).to_bytes(2, "big")
    (out / "sprites.bin").write_bytes(spr)
    (out / "beam.bin").write_bytes(beam(char_rom, char_lut, pal))

    spr_cols = colours(FIGHTER[0])[1:]
    regs = [(0x180 + 2 * i, c) for i, c in enumerate(PALETTE)]
    regs += [(0x1A2 + 8 * pair + 2 * i, c) for pair in range(2) for i, c in enumerate(spr_cols)]
    inc.append("COPPER_PALETTE\tmacro\t\t; playfield 0-15, sprite pairs 0/1 and 2/3")
    for i in range(0, len(regs), 8):
        inc.append("\tdc.w\t" + ",".join(f"${r:04x},${c:03x}" for r, c in regs[i : i + 8]))
    inc.append("\tendm")
    (out / "gfx.i").write_text("\n".join(inc) + "\n")

    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new("RGB", (8 * 17 + 1, 17 * ((len(sheet) + 7) // 8) + 1), (40, 40, 40))
    for i, pix in enumerate(sheet):
        for y in range(16):
            for x in range(16):
                c = PALETTE[pix[y][x]]
                rgb = ((c >> 8) * 17, (c >> 4 & 15) * 17, (c & 15) * 17)
                img.putpixel((1 + (i % 8) * 17 + x, 1 + (i // 8) * 17 + y), rgb)
    img.resize((img.width * 4, img.height * 4), Image.NEAREST).save(out / "sheet.png")


if __name__ == "__main__":
    main()
