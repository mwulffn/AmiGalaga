"""Build the stars: the near ones' copper table and fade schedule, and the far ones.

stars.bin   one copper table: 512 entries (256 lines, stored twice so any of
            the 256 start offsets can run a full frame), each entry

                MOVE SPR7POS, hpos      (0 = parked in horizontal blank)
                MOVE COLOR29, colour
                MOVE COLOR30, 0         (the colour of a far star on this line: the
                                         game writes it every frame)
                WAIT end of this line   (vertical position masked, except bit 7)

            Colours are the stars' brightness at tick 0 of the schedule.
starev.bin  the fade schedule, one tick per frame, looping after TICKS frames.
            Per tick: (offset of a colour word in the table, new colour) pairs,
            then -1. The last tick ends with -2 instead.

Every star keeps its line, column and hue for good. Each one fades between
off and full brightness in FADE_STEPS steps, on its own period and phase.

stars2.bin  the far stars, a second and slower layer on another sprite: FAR_STARS
            pairs of (line at rest, sprite x), in the order of their lines, and all
            of them a second time so that a run of FAR_STARS can start at any of
            them. No two are closer than FAR_APART lines, the last and the first
            round the 256 lines included: a sprite needs a line between two uses.
looks2.bin  how each far star looks, 16 bytes a star: how fast it twinkles (steps
            of the game's brightness wave each time its turn comes), where in the
            wave it starts, and its colour at brightness 0 to FADE_STEPS: one of
            the near stars' hues at half their brightness.
stars2.i    FAR_STARS for the assembler.
"""

import random
import sys
from pathlib import Path

LINES = 256
PLAYW = 224
FIRST_LINE = 44  # raster line of the first displayed line ($2c)
DENSITY = 0.78  # chance that a line has a star; about half are lit at a time
MIN_DX = 2  # stars within two lines of each other must be further apart than this
TICKS = 256  # schedule length in frames
CYCLES = (2, 3, 4)  # blink cycles per schedule: periods of 128, 85 and 64 frames
FADE_STEPS = 3
STEP_FRAMES = 4  # frames between fade steps
ENTRY = 16  # bytes per table entry
FAR_STARS = 24
FAR_APART = 4  # lines between two far stars, at least
FAR_BRIGHTNESS = 0.5  # of a near star's
FAR_RATES = (
    1,
    2,
    3,
)  # steps of the brightness wave a turn: slow, middling and quick twinklers
FAR_WAVE = 32  # steps in the game's brightness wave (stars.s)
FAR_LOOK = 16  # bytes a star in looks2.bin
# Arcade star colours: 2 bits per gun -> these 12-bit levels (measured in MAME).
RG, B = (0x0, 0x4, 0x9, 0xD), (0x0, 0x5, 0xA, 0xF)
COLOURS = [r << 8 | g << 4 | b for r in RG for g in RG for b in B][1:]


def dim(colour: int, level: int, brightness: float = 1.0) -> int:
    """Colour at brightness level 0..FADE_STEPS, of `brightness` at its fullest."""
    guns = [(colour >> s & 15) * brightness * level / FADE_STEPS for s in (8, 4, 0)]
    r, g, b = (int(v + 0.5) for v in guns)
    return r << 8 | g << 4 | b


def main() -> None:
    out_dir = Path(sys.argv[1])
    rng = random.Random(1981)
    field: list[tuple[int, int] | None] = [None] * LINES
    for i in range(LINES):
        if rng.random() >= DENSITY:
            continue
        near = [field[(i + d) % LINES] for d in (-2, -1, 1, 2)]
        taken = [star[0] for star in near if star]
        while True:
            x = rng.randrange(0, PLAYW, 2)
            if all(abs(x - t) > MIN_DX for t in taken):
                break
        field[i] = (x, rng.choice(COLOURS))

    # Brightness level of every star at every tick.
    fade = FADE_STEPS * STEP_FRAMES
    level = [[0] * TICKS for _ in range(LINES)]
    for i, star in enumerate(field):
        if not star:
            continue
        cycles = rng.choice(CYCLES)
        phase = rng.randrange(TICKS)
        lit = rng.uniform(0.4, 0.6)  # share of a period spent lit
        for t in range(TICKS):
            period = TICKS / cycles
            p = ((t + phase) % TICKS) % period  # position in this star's period
            on = lit * period
            if p < on - fade:
                lv = FADE_STEPS
            elif p < on:  # fading out
                lv = FADE_STEPS - 1 - int(p - (on - fade)) // STEP_FRAMES
            elif p < period - fade:
                lv = 0
            else:  # fading in
                lv = 1 + int(p - (period - fade)) // STEP_FRAMES
            level[i][t] = lv

    table = bytearray()
    for i in range(2 * LINES):
        star = field[i % LINES]
        pos = (0x80 + star[0]) >> 1 if star else 0
        colour = dim(star[1], level[i % LINES][0]) if star else 0
        line = FIRST_LINE + i % LINES
        wait = 0x80DF if 128 <= line < 256 else 0x00DF
        for word in (0x0178, pos, 0x01BA, colour, 0x01BC, 0, wait, 0x80FE):
            table += word.to_bytes(2, "big")
    (out_dir / "stars.bin").write_bytes(table)

    events = bytearray()
    count = 0
    for t in range(TICKS):
        nxt = (t + 1) % TICKS  # tick t's events take the table to the next frame
        for i, star in enumerate(field):
            if star and level[i][nxt] != level[i][t]:
                events += (i * ENTRY + 6).to_bytes(2, "big")
                events += dim(star[1], level[i][nxt]).to_bytes(2, "big")
                count += 1
        events += (0xFFFE if t == TICKS - 1 else 0xFFFF).to_bytes(2, "big")
    (out_dir / "starev.bin").write_bytes(events)

    # The far stars: lines spread over the 256 with room between, each jittered a little.
    far_rng = random.Random(2026)
    pitch = LINES / FAR_STARS
    lines = [
        int(i * pitch + far_rng.uniform(0, pitch - FAR_APART)) for i in range(FAR_STARS)
    ]
    gaps = [(b - a) % LINES for a, b in zip(lines, lines[1:] + lines[:1])]
    assert lines == sorted(lines) and min(gaps) >= FAR_APART, (lines, gaps)
    far, looks = bytearray(), bytearray()
    for line in lines:
        x = far_rng.randrange(0, PLAYW, 2)
        far += bytes([line, (0x80 + x) >> 1])
        hue = far_rng.choice(COLOURS)
        look = bytes([far_rng.choice(FAR_RATES), far_rng.randrange(FAR_WAVE)])
        for lv in range(FADE_STEPS + 1):
            look += dim(hue, lv, FAR_BRIGHTNESS).to_bytes(2, "big")
        looks += look.ljust(FAR_LOOK, b"\0")
    (out_dir / "stars2.bin").write_bytes(far * 2)
    (out_dir / "looks2.bin").write_bytes(looks)
    (out_dir / "stars2.i").write_text(
        "; generated by tools/make_stars.py - do not edit\n"
        f"FAR_STARS\tequ\t{FAR_STARS}\t; stars in the far layer\n"
    )

    stars = sum(1 for s in field if s)
    lit0 = sum(1 for i in range(LINES) if level[i][0])
    print(
        f"{stars} stars, {lit0} lit at tick 0; table {len(table)} bytes, "
        f"schedule {len(events)} bytes, {count / TICKS:.1f} colour changes per frame"
    )


if __name__ == "__main__":
    main()
