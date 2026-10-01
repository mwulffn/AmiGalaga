"""Build the copper star tables for experiment-4.

One fixed starfield, one table per twinkle state (which stars are lit).
A table has 512 entries (256 lines, stored
twice so any of the 256 start offsets can run a full frame), each entry
three copper instructions:

    MOVE SPR7POS, hpos      (0 = parked in horizontal blank: no star)
    MOVE COLOR29, colour
    WAIT end of this line   (vertical position masked, except bit 7)

The WAIT's line bit 7 is preset for start offset 0; the demo patches the
few entries that cross raster lines 128 and 256 as the table scrolls.
"""

import random
import sys
from pathlib import Path

LINES = 256
PLAYW = 224
FIRST_LINE = 44  # raster line of the first displayed line ($2c)
DENSITY = 0.78  # chance that a line has a star; half of them are lit at a time
MIN_DX = 2  # stars within two lines of each other must be further apart than this
# Arcade star colours: 2 bits per gun -> these 12-bit levels (measured in MAME).
RG, B = (0x0, 0x4, 0x9, 0xD), (0x0, 0x5, 0xA, 0xF)
COLOURS = [r << 8 | g << 4 | b for r in RG for g in RG for b in B][1:]


def main() -> None:
    rng = random.Random(1981)
    # One fixed starfield: a line has at most one star, with its own x and
    # colour for good. Like the arcade, every star belongs to one of four sets
    # and two sets are lit at a time (one of sets 0/1, one of sets 2/3), toggled
    # at different rates, so a star only ever blinks on and off in place.
    # A star may not share a column (or the one next to it) with a star on the
    # two lines above or below, or the pair reads as one tall star. The check
    # wraps around, because the table scrolls as a loop.
    field: list[tuple[int, int, int] | None] = [None] * LINES
    for i in range(LINES):
        if rng.random() >= DENSITY:
            continue
        near = [field[(i + d) % LINES] for d in (-2, -1, 1, 2)]
        taken = [star[0] for star in near if star]
        while True:
            x = rng.randrange(0, PLAYW, 2)
            if all(abs(x - t) > MIN_DX for t in taken):
                break
        field[i] = (x, rng.choice(COLOURS), rng.randrange(4))
    out = bytearray()
    for state in range(4):
        lit = {state & 1, 2 + (state >> 1)}
        for i in range(2 * LINES):
            star = field[i % LINES]
            x, colour = star[:2] if star and star[2] in lit else (None, 0)
            pos = 0 if x is None else (0x80 + x) >> 1
            line = FIRST_LINE + i % LINES
            wait = 0x80DF if 128 <= line < 256 else 0x00DF
            for word in (0x0178, pos, 0x01BA, colour, wait, 0x80FE):
                out += word.to_bytes(2, "big")
    Path(sys.argv[1]).write_bytes(out)
    total = sum(1 for star in field if star)
    lit0 = sum(1 for star in field if star and star[2] in (0, 2))
    print(f"{len(out)} bytes, {total} stars in the field, {lit0} lit in twinkle state 0")


if __name__ == "__main__":
    main()
