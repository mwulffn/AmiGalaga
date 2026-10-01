"""How the arcade moves its formation: the drift and the breathing.

    python3 formation.py path/to/galaga.zip motion.bin

While a stage's waves arrive the whole formation drifts from side to side,
one pixel every four frames, up to 32 either way. Once every wave is in and
the drift is back at the middle, it stops, and the formation breathes
instead: every four frames each column and row may move one pixel outwards
(for 32 steps) or back in (for 32). Which ones move on a step comes from a
bit pattern per column and row that is rotated each step and reloaded every
eight; the outer columns and the bottom row move every step, the middle ones
rarely. Ported from the main CPU ($2A90 and $1DEC).

Both work on the two tables the flights read: home_loc (offset, origin per
column and row) and home_x (origin + offset, in pixels).

With a MAME trace (trace_motion.lua) every frame's tables are compared.
"""

import sys
from pathlib import Path

import galaga_motion as G

COLUMNS, ENTRIES, LIMIT = 10, 16, 32
REST_X = [49 + 16 * i for i in range(COLUMNS)] + [60, 76, 92, 104, 116, 128]
REST_LOC = [49 + 16 * i for i in range(COLUMNS)] + [146, 138, 130, 124, 118, 112]


class Formation:
    """One call of tick() per arcade frame."""

    def __init__(self, rom: G.Rom) -> None:
        self.patterns = rom.main[G.BREATHE_PATTERNS : G.BREATHE_PATTERNS + 4 * ENTRIES]
        self.offset = [0] * ENTRIES
        self.drifting, self.leftwards = True, False
        self.count, self.bits = 0, [0] * ENTRIES
        self.opening = True  # for the pulse sound

    @property
    def home_loc(self) -> bytes:
        return bytes(v for o, c in zip(self.offset, REST_LOC) for v in (o & 0xFF, c))

    @property
    def home_x(self) -> bytes:
        return bytes(v for o, c in zip(self.offset, REST_X) for v in ((c + o) & 0xFF, 0))

    def tick(self, frame: int, all_in: bool, empty: bool = False) -> None:
        """all_in: every wave has been launched and has landed. empty: and nobody stayed."""
        if all_in and empty and self.drifting:
            return  # a challenging stage: nothing to settle
        if not self.drifting:
            if frame & 3 == 0:
                self.breathe()
        elif (frame - 1) & 3 == 0:
            step = -1 if self.leftwards else 1
            for i in range(COLUMNS):
                self.offset[i] += step
            if all_in and self.offset[0] == 0:
                self.drifting = False
            elif abs(self.offset[0]) == LIMIT:
                self.leftwards = self.offset[0] > 0

    def breathe(self) -> None:
        old = self.count
        self.opening = not old & 0x80
        self.count = (old + 1 if self.opening else old - 1) & 0xFF
        if old == 0x1F:
            self.count |= 0x80
        if old == 0x81:
            self.count &= 0x7F
        if old & 7 == 0:
            at = ENTRIES * (self.count >> 3 & 3)
            self.bits = list(self.patterns[at : at + ENTRIES])
        outwards = 1 if self.opening else -1
        for i in range(ENTRIES):
            moves, self.bits[i] = self.bits[i] & 1, self.bits[i] >> 1 | (self.bits[i] & 1) << 7
            if moves:  # the left five columns go left to open; everything else right, or down
                self.offset[i] += -outwards if i < COLUMNS // 2 else outwards


def main() -> None:
    import validate as V

    rom = G.Rom(sys.argv[1])
    data = Path(sys.argv[2]).read_bytes()
    recs = [data[i : i + V.REC] for i in range(0, len(data) - V.REC + 1, V.REC)]
    slots = lambda r: [r[1 + 20 * i : 21 + 20 * i] for i in range(12)]  # noqa: E731
    tables = lambda r: (bytes(V.env_of(r).home_loc), bytes(V.env_of(r).home_x[i] for i in range(0, 32, 2)))  # noqa: E731
    form, stage, same, differ, stages, all_in = None, 0, 0, 0, set(), False
    for t in range(9, len(recs)):
        if recs[t][V.REC - 1] != stage:
            stage, form, launched, started, all_in = recs[t][V.REC - 1], None, 0, False, False
        if (stage + 1) & 3 == 0:
            continue  # a challenging stage has no formation
        loc, x = tables(recs[t])
        if form is None:  # the arcade resets the tables at the start of a stage
            rest = Formation(rom)  # a breathing formation passes through rest too: look for the drift's first step
            ahead = [bytes(V.env_of(recs[u]).home_loc) for u in range(t, min(t + 6, len(recs)))]
            rest.tick(1, False)
            if loc == Formation(rom).home_loc and rest.home_loc in ahead:
                form = Formation(rom)
            continue
        before, now = slots(recs[t - 1]), slots(recs[t])
        launched += sum(1 for b, s in zip(before, now) if s[0x13] & 1 and not b[0x13] & 1 and s[0x10] < 0x38)
        launched += sum(1 for b, s in zip(before, now) if s[0x13] & 1 and not b[0x13] & 1 and 0x40 <= s[0x10] < 0x60)
        if not started:  # and holds the drift until the stage begins
            started = loc != form.home_loc
            if not started:
                continue
        all_in = all_in or (launched >= 40 and not any(s[0x13] & 1 for s in slots(recs[t - 2])))
        form.tick(recs[t][0], all_in)
        want = (form.home_loc, bytes(form.home_x[i] for i in range(0, 32, 2)))
        if want == (loc, x):
            same += 1
            stages.add(stage)
        else:
            differ += 1
            if differ <= 5:
                print(f"frame {t} (counter {recs[t][0]}), stage {stage}:")
                print("  model", list(want[1]), "\n  trace", list(x))
    print(f"formation: stages {sorted(stages)}, {same} frames with the arcade's tables, {differ} without")


if __name__ == "__main__":
    main()
