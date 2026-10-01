"""The enemy that transforms: when the arcade picks it, how long it flashes, when it leaves.

    python3 transform.py path/to/galaga.zip game.bin [motion.bin]

From stage 4 on (not on challenging stages), once a stage's waves are in and
fewer than 10 enemies are left, the first bee at rest in the formation (or,
with no bee, the first butterfly) is picked. It flashes between its own
colours and those of what it will become for 64 arcade frames, then dives as
a scorpion, a spy ship or a flagship (by stage), and two more of the same
split off it on the way (the script's "spawn" token; objects $38 to $3E, the
ones that otherwise fly through at the entrance). Shooting all three brings a
bonus. One that is not shot and comes home is its old self again. A stage has
one transformation at most: if the picked enemy is shot or leaves its place
while it flashes, there is none.

Ported from the main CPU ($1A80) and the sub CPU's spawn token ($097B).

With a trace from trace_game.lua the manager is checked frame by frame: its
timer, the object it picked, and whether it is still on are predicted from
the frame before. With a trace from trace_motion.lua the spawned enemies are
checked: the slot and object the spawn takes, and its first frame of flight.
"""

import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import galaga_motion as G

FLASH = 0xC0  # the timer starts here and counts up to 0: 64 arcade frames
WAIT = 0xE0  # and is put back to this if the fighter is not in play when it runs out
NONE = 1  # no object is picked
LIMIT = 10  # one is picked once fewer than this many enemies are left
SCRIPTS = {4: 0x04EA, 5: 0x0473, 6: 0x04AB}  # the dive of each kind, by its colour set
BONUS = {4: 3000, 5: 1000, 6: 2000}  # for shooting all three
EXTRAS = (0x38, 0x3A, 0x3C, 0x3E)  # the objects a spawn can use
CANDIDATES = (*range(0x08, 0x30, 2), *range(0x40, 0x60, 2))  # bees first, then butterflies


def limit(stage: int) -> int:
    """How few enemies must be left before one transforms: never before stage 4 or on a challenging stage."""
    return 0 if stage < 3 or stage & 3 == 3 else LIMIT


def colour(stage: int) -> int:
    """The colour set of what the stage's enemy transforms into: 4 flagship, 5 scorpion, 6 spy ship."""
    return (stage >> 2) % 3 + 4


@dataclass
class Transform:
    """One call of tick() per arcade frame."""

    on: bool = False  # from the moment the waves are in until it has sent one off, or lost it
    timer: int = 0
    obj: int = NONE
    colour: int = 0
    picked: bool = False  # this frame: for the sound

    def tick(self, alive: int, stage: int, resting: Callable[[int], bool], in_play: bool) -> int | None:
        """The object to send off on its dive this frame, if any."""
        self.picked = False
        if not self.on or alive >= limit(stage):
            return None
        if self.timer == 0:
            for obj in CANDIDATES:
                if resting(obj):
                    self.timer, self.obj, self.colour, self.picked = FLASH, obj, colour(stage), True
                    break
            return None
        if self.timer != 0xFF:
            self.timer += 1
            if not resting(self.obj):  # shot, or gone diving, while it flashed
                self.on = False
            return None
        if not in_play:
            self.timer = WAIT
            return None
        self.on = False
        return self.obj if resting(self.obj) else None

    def flashing(self) -> bool:
        """While it flashes: is it showing its new colours?"""
        return bool(self.timer & 0x10)


def spawn(leader: bytes, script: int, obj: int) -> bytes:
    """The 20 bytes of a flight split off its leader, before its first step.

    The arcade writes only these; the slot's bytes 6, 7, $0E and $0F (where its home is,
    its bomb timer and its chances to bomb) are whatever its last user left there, so
    whether a spawned enemy bombs is an accident. Here, and in the game, it never does.
    """
    s = bytearray(20)
    s[0:6] = leader[0:6]  # where it is and how it is heading
    s[8], s[9] = script & 0xFF, script >> 8
    s[0x0A], s[0x0B], s[0x0D] = 1, 2, 1  # its first step is loaded when it is next stepped
    s[0x10], s[0x13] = obj, leader[0x13]
    return bytes(s)


def check_manager(path: str) -> None:
    import game_trace as T

    frames = T.load(path)
    timer_at, task_at = T.PLAYER + 0x21, T.TASKS + 4
    ok = bad = picks = launches = ended = 0
    for t in range(1, len(frames)):
        was, now = frames[t - 1], frames[t]
        if not was.byte(task_at) or (now.byte(T.FRAME) - was.byte(T.FRAME)) & 0xFF != 1:
            continue
        stage = was.byte(T.STAGE)
        m = Transform(True, was.byte(timer_at), was.byte(T.SPECIAL), was.byte(T.SPECIAL + 2))
        resting = {obj for obj in CANDIDATES if was.state(obj) == 1}
        go = m.tick(was.byte(T.ALIVE), stage, resting.__contains__, bool(was.byte(T.TASKS + 0x15)))
        got = (now.byte(timer_at), now.byte(T.SPECIAL), bool(now.byte(task_at)))
        launched = go is not None and now.state(go) == 9
        if (m.timer, m.obj, m.on) == got and (go is None or launched):
            ok += 1
            picks += m.picked
            launches += launched
            if m.picked and now.byte(T.SPECIAL + 2) != m.colour:
                bad += 1
                print(f"frame {t}: colour set {now.byte(T.SPECIAL + 2)}, model {m.colour}")
        elif (m.timer, m.obj) == got[:2] and go is None:
            ended += 1  # switched off from outside: the stage is over
        else:
            bad += 1
            if bad <= 10:
                print(f"frame {t} stage {stage}: model {(m.timer, m.obj, m.on, go)}, arcade {got}")
    print(
        f"manager: {ok} frames as the arcade, {bad} not; {picks} picked, {launches} sent off;"
        f" switched off {ended} times by the end of a stage"
    )


def check_spawns(rom: G.Rom, path: str) -> None:
    import validate as V

    data = Path(path).read_bytes()
    recs = [data[i : i + V.REC] for i in range(0, len(data) - V.REC + 1, V.REC)]
    slot = lambda r, i: r[1 + 20 * i : 21 + 20 * i]  # noqa: E731
    ok = bad = 0
    for t in range(1, len(recs)):
        was, now = recs[t - 1], recs[t]
        for i in range(12):
            lead = slot(was, i)
            p = lead[8] | lead[9] << 8
            if not lead[0x13] & 1 or lead[0x0D] != 1 or rom.sub[p] != 0xF2:
                continue
            # the first of the four objects that is idle, and the last free slot
            states = V.env_of(was).obj_state
            obj = next((o for o in EXTRAS if states[o] & 0x80), None)
            at = next((j for j in range(11, -1, -1) if not slot(was, j)[0x13] & 1), None)
            if obj is None or at is None:
                continue
            s = bytearray(spawn(lead, rom.sub[p + 1] | rom.sub[p + 2] << 8, obj))
            if at > i:  # a slot after its leader's is stepped in the same frame
                G.step(s, rom, V.env_of(now))
            got = bytearray(slot(now, at))
            for k in (6, 7, 0x0E, 0x0F, 0x11, 0x12):  # left over, or rewritten by the formation update
                s[k] = got[k] = 0
            if s == got:
                ok += 1
            else:
                bad += 1
                print(f"frame {t}: slot {at}\n  model  {bytes(s).hex(' ')}\n  arcade {bytes(got).hex(' ')}")
    print(f"spawns: {ok} as the arcade, {bad} not (the bytes the arcade leaves as they were not compared)")


def main() -> None:
    rom = G.Rom(sys.argv[1])
    check_manager(sys.argv[2])
    if len(sys.argv) > 3:
        check_spawns(rom, sys.argv[3])


if __name__ == "__main__":
    main()
