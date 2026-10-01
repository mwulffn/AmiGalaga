"""How the arcade sends a stage's enemies in: the wave table and the launcher.

    python3 waves.py path/to/galaga.zip motion.bin

A stage row (see extract.py) is turned into a table of five waves, each a
list of (control byte, object) pairs: first half and second half of the wave
alternately. A task then launches one enemy per frame at most: a wave starts
once nothing is flying (it hears of a landing one frame late; on a challenging
stage a timer adds one to two counts of 32 frames after that), an enemy whose control byte has bit 7 clear waits for
the frame counter to reach a multiple of 8, and one with bit 7 set follows
the frame after its partner. Ported from the main CPU ($25A2 and $2916).

From stage 4 on a wave can have extra enemies that only fly through: two or
four, objects $38 to $3E, put at random places among the wave's eight, half
of them in each half of the wave. The arcade's random numbers come from the
Z80's refresh register, so they cannot be reproduced; wave_table takes the
random source as an argument. In the launcher an extra enemy looks like a
butterfly if its table entry has bit 6 set, else a bee, or a boss in the
stage's second wave.

With a MAME trace (trace_motion.lua) the launcher is checked against every
launch of the stages it covers. For a stage with extras the places they were
given are read from the trace's own order of launches, and the check is that
the table built with those places launches each enemy at the arcade's frame.
"""

import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import galaga_motion as G

WAVE_START, WAVE_END = 0x7E, 0x7F
RANK = 3  # the difficulty switch: row of the stage index table. 3 is what MAME's default gives.


class Random:
    """The game's random bytes (game/src/stage.s, Random), as a test build makes them."""

    def __init__(self) -> None:
        self.seed = 0

    def __call__(self) -> int:
        self.seed = (self.seed * 25173 + 13849) & 0xFFFF
        return self.seed >> 8


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


def extras_of(row: bytes) -> list[int]:
    """How many enemies only fly through in each of a stage row's five waves."""
    return [row[2 + 3 * w] & 0x0F for w in range(5)]


def extra_object(b: int) -> int:
    """The object number of a wave's b'th extra enemy, counting down from how many it has."""
    return 0x38 | (2 * b & 6)


def wave_table(rom: G.Rom, stage: int, rank: int = RANK, rnd: Callable[[], int] | None = None) -> bytes:
    """The stage's table of (control, object) pairs. rnd gives a random byte per call."""
    row, out = stage_row(rom, stage, rank), bytearray()
    for w in range(5):
        extras, first, second = row[2 + 3 * w : 5 + 3 * w]
        objs = rom.main[G.WAVE_OBJECTS + 8 * w : G.WAVE_OBJECTS + 8 * w + 8]
        # 16 places: 8 for each half of the wave. The extras take theirs first, at random
        # among the first 4 + (half their number) of a half; odd ones go in the second half.
        places = [0xFF] * 16
        n = extras & 0x0F
        for b in range(n, 0, -1):
            while True:
                assert rnd is not None, "this stage has extra enemies: wave_table needs a random source"
                a = rnd() % (n // 2 + 4) | (8 if b & 1 else 0)
                if places[a] == 0xFF:
                    break
            # the top bits of the row's byte, one per extra: set = it looks like a butterfly
            places[a] = extra_object(b) | (0x40 if extras & 0x80 else 0)
            extras = extras << 1 & 0xFF
        at = 0
        for k, obj in enumerate(objs):  # the wave's own eight take the places left, in order
            while places[at] != 0xFF:
                at += 1
            places[at] = obj
            at = 8 if k == 3 else at + 1
        out.append(WAVE_START)
        i = 0
        while places[i] != 0xFF:
            out += bytes((first, places[i], second, places[i + 8]))
            i += 1
    out.append(WAVE_END)
    return bytes(out)


@dataclass
class Launch:
    obj: int
    script: int
    start: tuple[int, int, int]  # y, x, heading as FlightLaunch wants them
    mirror: bool
    path: int = 0  # which entry path: odd ones come in from the sides
    look: str = ""  # an extra enemy's kind: "butterfly", "bee" or "boss"; the others have their own


class Launcher:
    """One call of tick() per arcade frame."""

    def __init__(self, rom: G.Rom, stage: int, rank: int = RANK, rnd: Callable[[], int] | None = None) -> None:
        self.table, self.at = wave_table(rom, stage, rank, rnd), 0
        self.wave = 0  # which wave is coming in, 1 to 5
        self.entries, self.starts = rom.entry_paths(), rom.start_positions()
        self.flying = 0  # how many were flying a frame ago: the arcade hears of a landing a frame late
        self.all_in = False  # every wave launched, and nothing flying since
        self.challenge = stage & 3 == 3
        self.timer = 2  # the arcade's game timer 0: on a challenging stage it spaces the waves
        self.wave_hits = 0  # challenging stage: enemies of this wave still to shoot for its bonus
        self.heard = 0

    def done(self) -> bool:
        return self.table[self.at] == WAVE_END

    def tick(self, frame: int, flying: int, free_slot: bool, enabled: bool = True) -> Launch | None:
        """enabled: False while the fighter is being replaced; no new wave starts then."""
        c = self.table[self.at]
        flying, self.flying = self.flying, flying
        self.heard = flying  # what the arcade's logic takes the number flying to be this frame
        timer = self.timer
        if frame & 31 == 0 and self.timer:  # the timers count after the launcher has had its turn
            self.timer -= 1
        if c == WAVE_END:
            self.all_in = self.all_in or not flying
            return None
        if c == WAVE_START:
            if not enabled:
                return None
            if flying:
                self.timer = 2
            elif self.challenge and timer == 1:
                self.wave_hits = 8  # the next wave's eight count for its bonus
            elif not (self.challenge and timer):
                self.at += 1
                self.wave += 1
            return None
        if (not c & 0x80 and frame & 7) or not free_slot:
            return None
        obj = self.table[self.at + 1]
        self.at += 2
        script, k = self.entries[c & 0x3F]
        mirror = bool(c & 0x40)
        look = ""
        if obj & 0x38 == 0x38:  # one that only flies through
            look = "butterfly" if obj & 0x40 else "boss" if self.wave == 2 else "bee"
            obj &= 0x3F
        return Launch(obj, script, self.starts[2 * k + mirror], mirror, c & 0x3F, look)


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


    def places(t: int, stage: int) -> list[int] | None:
        """Where the arcade put the stage's extra enemies, as the random numbers that would
        put them there, read from the order of the launches from frame t on."""
        extras = extras_of(stage_row(rom, stage))
        want, seen = sum(8 + n for n in extras), []
        while t < len(recs) and stage_of(recs[t]) == stage and len(seen) < want:
            seen += [s[0x10] for s in launched(t)]
            t += 1
        if len(seen) < want:
            return None  # the trace does not have the whole entrance
        out = []
        for n in extras:
            wave, seen = seen[: 8 + n], seen[8 + n :]
            for b in range(n, 0, -1):  # launches alternate: first half, second half
                if extra_object(b) not in wave[b & 1 :: 2]:
                    return None
                out.append(wave[b & 1 :: 2].index(extra_object(b)))
        return out

    launcher, stage, ok, bad, covered, held, skipped = None, 0, 0, 0, set(), set(), set()
    for t in range(1, len(recs)):
        if stage_of(recs[t]) != stage:
            stage = stage_of(recs[t])
            launcher, waiting = None, True
            if stage:
                rnd = places(t, stage)
                if rnd is None:
                    skipped.add(stage)
                else:
                    launcher = Launcher(rom, stage, rnd=iter(rnd).__next__)
        if launcher is None or launcher.done():
            continue
        if waiting:  # the arcade holds the first wave back while it shows the stage number
            waiting = not any(launched(u) for u in range(t, min(t + 8, len(recs))))
            if waiting:
                continue
            launcher.timer = 0  # the trace is joined at the first wave: its wait is over
        before = slots(recs[t - 1])
        flying = sum(s[0x13] & 1 for s in before)
        want = launcher.tick(recs[t][0], flying, any(not s[0x13] & 1 for s in before))
        seen = launched(t)
        if want is None and not seen:
            continue
        if want and not seen and launcher.table[launcher.at - 3] == WAVE_START:
            launcher.at -= 2  # the arcade is holding the wave back (the fighter was lost): try again
            held.add((t // 600, stage & 3 == 3))
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
    if skipped:
        print(f"  stages {sorted(skipped)} left out: their extra enemies' places could not be read from the trace")
    print(
        f"  ({len(held)} waves were held back by the arcade, as it does while the fighter is replaced;"
        f" {sum(c for _, c in held)} of them on challenging stages)"
    )


if __name__ == "__main__":
    main()
