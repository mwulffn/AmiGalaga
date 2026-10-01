"""How the arcade sends a stage's enemies in: the wave table and the launcher.

    python3 waves.py path/to/galaga.zip motion.bin

A stage row (see extract.py) is turned into a table of five waves, each a
list of (control byte, object) pairs: first half and second half of the wave
alternately. A task then launches one enemy per frame at most: a wave starts
once nothing is flying (it hears of a landing one frame late), an enemy whose control byte has bit 7 clear waits for
the frame counter to reach a multiple of 8, and one with bit 7 set follows
the frame after its partner. Ported from the main CPU ($25A2 and $2916).

Enemies that only fly through ("transients", stage 4 on) are not built yet.

With a MAME trace (trace_motion.lua) the launcher is checked against every
launch of the stages it covers.
"""

import sys
from dataclasses import dataclass
from pathlib import Path

import galaga_motion as G

WAVE_START, WAVE_END = 0x7E, 0x7F
RANK = 3  # the difficulty switch: row of the stage index table. 3 is what MAME's default gives.


def stage_row(rom: G.Rom, stage: int, rank: int = RANK) -> bytes:
    """The 18-byte stage data row for stage 1, 2, 3..."""
    a = stage
    while a >= 0x17:
        a -= 4
    m = rom.main
    if (a + 1) & 3 == 0:  # every fourth stage is a challenging stage
        at = G.CHALLENGE_DATA + m[G.CHALLENGE_IDX + ((stage >> 2) & 7)]
    else:
        at = G.STAGE_DATA + m[G.STAGE_IDX + 17 * rank + a - (a >> 2) - 1]
    return m[at : at + 18]


def wave_table(rom: G.Rom, stage: int, rank: int = RANK) -> bytes:
    row, out = stage_row(rom, stage, rank), bytearray()
    for w in range(5):
        _extras, first, second = row[2 + 3 * w : 5 + 3 * w]
        objs = rom.main[G.WAVE_OBJECTS + 8 * w : G.WAVE_OBJECTS + 8 * w + 8]
        out.append(WAVE_START)
        for i in range(4):
            out += bytes((first, objs[i], second, objs[4 + i]))
    out.append(WAVE_END)
    return bytes(out)


@dataclass
class Launch:
    obj: int
    script: int
    start: tuple[int, int, int]  # y, x, heading as FlightLaunch wants them
    mirror: bool


class Launcher:
    """One call of tick() per arcade frame."""

    def __init__(self, rom: G.Rom, stage: int, rank: int = RANK) -> None:
        self.table, self.at = wave_table(rom, stage, rank), 0
        self.entries, self.starts = rom.entry_paths(), rom.start_positions()
        self.flying = 0  # how many were flying a frame ago: the arcade hears of a landing a frame late

    def done(self) -> bool:
        return self.table[self.at] == WAVE_END

    def tick(self, frame: int, flying: int, free_slot: bool) -> Launch | None:
        c = self.table[self.at]
        flying, self.flying = self.flying, flying
        if c == WAVE_END:
            return None
        if c == WAVE_START:
            if not flying:
                self.at += 1
            return None
        if (not c & 0x80 and frame & 7) or not free_slot:
            return None
        obj = self.table[self.at + 1]
        self.at += 2
        script, k = self.entries[c & 0x3F]
        mirror = bool(c & 0x40)
        return Launch(obj, script, self.starts[2 * k + mirror], mirror)


def main() -> None:
    import validate as V

    rom = G.Rom(sys.argv[1])
    data = Path(sys.argv[2]).read_bytes()
    recs = [data[i : i + V.REC] for i in range(0, len(data) - V.REC + 1, V.REC)]
    slots = lambda r: [r[1 + 20 * i : 21 + 20 * i] for i in range(12)]  # noqa: E731
    stage_of = lambda r: r[V.REC - 1]  # noqa: E731
    launched = lambda t: [  # noqa: E731
        s for b, s in zip(slots(recs[t - 1]), slots(recs[t])) if s[0x13] & 1 and not b[0x13] & 1 and s[0x10] < 0x60
    ]
    launcher, stage, ok, bad, covered, held = None, 0, 0, 0, set(), set()
    for t in range(1, len(recs)):
        if stage_of(recs[t]) != stage:
            stage = stage_of(recs[t])
            row = stage_row(rom, stage)
            plain = stage and not any(row[2 + 3 * w] for w in range(5))
            launcher, waiting = (Launcher(rom, stage) if plain else None), True
        if launcher is None or launcher.done():
            continue
        if waiting:  # the arcade holds the first wave back while it shows the stage number
            waiting = not any(launched(u) for u in range(t, min(t + 8, len(recs))))
            if waiting:
                continue
        before = slots(recs[t - 1])
        flying = sum(s[0x13] & 1 for s in before)
        want = launcher.tick(recs[t][0], flying, any(not s[0x13] & 1 for s in before))
        seen = launched(t)
        if want is None and not seen:
            continue
        if want and not seen and launcher.table[launcher.at - 3] == WAVE_START:
            launcher.at -= 2  # the arcade is holding the wave back (the fighter was lost): try again
            held.add(t // 600)
            continue
        covered.add(stage)
        got = (seen[0][0x10], bool(seen[0][0x13] & 0x80)) if len(seen) == 1 else None
        if want and got == (want.obj, want.mirror):
            ok += 1
        else:
            bad += 1
            if bad <= 10:
                print(f"frame {t} (counter {recs[t][0]}), stage {stage}: model {want}, trace {got}")
    print(f"launcher: stages {sorted(covered)}, {ok} launches at the frame the arcade made them, {bad} not")
    print(f"  ({len(held)} waves were held back by the arcade, as it does while the fighter is replaced)")


if __name__ == "__main__":
    main()
