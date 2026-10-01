"""Which enemy leaves the formation to attack, and when: the arcade's rules.

    python3 dives.py path/to/galaga.zip game.bin

Ported from the main CPU ($1B65, $0857 and what they call). Every 16 frames
three timers count down: bosses, butterflies, bees. One that reaches zero
sends an enemy of its kind, if fewer than the stage's limit are flying, and
is reloaded with a value that depends on the stage, on how many enemies are
left and on how long the stage has lasted.

  - A bee or butterfly: the first one, in object order, that is in its place.
  - A boss: every other time (if no boss is busy capturing) the first boss
    in its place sets off alone to capture the fighter. Otherwise a boss
    goes with two of the three butterflies under it, or failing that with
    one, or alone; they are queued and leave on successive frames. A
    captured fighter parked above the boss goes along.

A dive starts where the enemy is in the formation, heading up, and flies its
kind's script, mirrored for enemies on the right.

With a trace from trace_game.lua, every frame's timers, queue and launches
are predicted from the frame before and compared.
"""

import sys
from dataclasses import dataclass, field

import galaga_motion as G

BEE_DIVE, BUTTERFLY_DIVE, BOSS_DIVE, ROGUE_DIVE, CAPTURE_DIVE = 0x034F, 0x03A9, 0x0411, 0x0444, 0x0454
BEES, BUTTERFLIES = range(0x08, 0x30, 2), range(0x40, 0x60, 2)
BOSSES = (0x30, 0x32, 0x34, 0x36)  # in object order; left to right they are 30 34 36 32
ESCORTS = (0x4A, 0x52, 0x5A, 0x58, 0x50, 0x48)  # the butterflies under the bosses, right to left
FIGHTERS = range(0x00, 0x08, 2)
IN_PLACE, DIVING = 1, 9  # object states
EMPTY = 0xFF
# main ROM tables for the timers' reload values
BUTTERFLY_RELOAD, BEE_RELOAD, BOMB_FLAGS, BOSS_RELOAD = 0x08CD, 0x08EB, 0x0909, 0x0929
STAGE_CONFIG_INDEX, STAGE_CONFIG_SIZE = 0x2C65, 0x82  # per rank: address of 26 stages x 5 bytes
FIRST_TIMERS = (0x16, 0x02, 0x02)
STAGE_TIME, TIME_EARLY, TIME_MID = 0x78, 0x3C, 0x28  # the stage timer counts down every 32 frames


def stage_parms(rom: G.Rom, stage: int, rank: int = 3) -> list[int]:
    """The stage's ten settings, a nibble each."""
    a = stage
    while a >= 0x1B:
        a -= 4
    at = rom.word(rom.main, STAGE_CONFIG_INDEX + 2 * rank) + 5 * (a - 1)
    return [n for b in rom.main[at : at + 5] for n in (b >> 4, b & 15)]


@dataclass
class Launch:
    obj: int
    script: int
    mirror: bool


@dataclass
class Dives:
    """One call of tick() per arcade frame. The caller owns the enemies' states."""

    rom: G.Rom
    parms: list[int]
    timers: list[int] = field(default_factory=lambda: list(FIRST_TIMERS))
    reload: list[int] = field(default_factory=lambda: [2, 2, 2])
    queue: list[int] = field(default_factory=lambda: [EMPTY] * 12)  # 4 x (object | mirror, script lo, hi)
    max_flying: int = 0
    bomb_flags: int = 0
    capturing: int = 0  # a boss is out to capture: the next bosses take escorts
    capture_boss: int = 0
    toggle: int = 0
    special: int = 0  # the enemy that is about to transform does not dive
    bonus: list[int] = field(default_factory=lambda: [0] * 4)  # per boss: escorts it last left with

    def settings(self, stage_time: int, alive: int, last_stand: bool) -> None:
        """Every frame: the limits and reload values for the state of the stage ($0857)."""
        m, p = self.rom.main, self.parms
        if stage_time < TIME_EARLY:
            self.max_flying = p[5]
        self.bomb_flags = m[BOMB_FLAGS + 4 * p[0] + alive // 10]
        if last_stand:
            self.reload = [2, 2, 2]
            return
        late = (stage_time < TIME_MID) + (stage_time == 0)
        self.reload = [
            m[BOSS_RELOAD + 4 * p[1] + alive // 10],
            m[BUTTERFLY_RELOAD + 3 * p[2] + late],
            m[BEE_RELOAD + 3 * p[3] + late],
        ]

    def tick(self, frame: int, state: dict[int, int], flying: int, free_slot: bool) -> Launch | None:
        q = self.queue
        for n in range(0, 12, 3):  # someone queued leaves first
            if q[n] != EMPTY:
                obj, mirror, q[n] = q[n] & 0x7F, bool(q[n] & 0x80), EMPTY
                if state[obj] != IN_PLACE or not free_slot:
                    return None
                return Launch(obj, q[n + 1] | q[n + 2] << 8, mirror)
        if frame & 15:
            return None
        for kind in range(3):
            self.timers[kind] = (self.timers[kind] - 1) & 0xFF
            if self.timers[kind] == 0:
                break
        else:
            return None
        if flying >= self.max_flying:
            self.timers[kind] += 1  # try again in 16 frames
            return None
        self.timers[kind] = self.reload[kind]
        if kind == 0:
            self.boss(state)
            return None
        objects, script = ((BUTTERFLIES, BUTTERFLY_DIVE), (BEES, BEE_DIVE))[kind - 1]
        for obj in objects:
            if state[obj] == IN_PLACE and obj != self.special:
                return Launch(obj, script, bool(obj & 2)) if free_slot else None
        return None

    def boss(self, state: dict[int, int]) -> None:
        if not self.capturing:
            self.toggle = (self.toggle + 1) & 0xFF
            if not self.toggle & 1:
                for boss in BOSSES:
                    if state[boss] == IN_PLACE:
                        self.capturing, self.capture_boss = 1, boss
                        self.send(boss, CAPTURE_DIVE, [], state)
                        return
                return
        # bit 5 = the rightmost escort ... bit 0 = the leftmost; boss n (4 = leftmost) has bits n-4 .. n-2
        there = [state[e] == IN_PLACE and e != self.special for e in ESCORTS]
        for want in (2, 1):
            for n in (4, 3, 2, 1):
                mine = [i for i in (n + 1, n, n - 1) if there[i]]  # leftmost first
                boss = 0x30 + 2 * ((n ^ 1 if n & 2 else n) & 3)
                if len(mine) >= want and state[boss] == IN_PLACE:
                    self.send(boss, BOSS_DIVE, [ESCORTS[i] for i in mine[:want]], state)
                    return
        for boss in BOSSES:
            if state[boss] == IN_PLACE:
                self.send(boss, BOSS_DIVE, [], state)
                return
        for fighter in FIGHTERS:  # a captured fighter whose boss is gone
            if state[fighter] == IN_PLACE:
                self.queue[0:3] = [fighter | (0x80 if fighter & 2 else 0), ROGUE_DIVE & 255, ROGUE_DIVE >> 8]
                return

    def send(self, boss: int, script: int, escorts: list[int], state: dict[int, int]) -> None:
        """Queue a boss, its escorts and its captured fighter: they leave on successive frames."""
        side = 0x80 if boss & 2 else 0
        self.bonus[(boss & 7) >> 1] = len(escorts)  # decides what the boss scores if shot on the way
        group = [boss, *escorts]
        if state[boss & 7] == IN_PLACE:
            group.append(boss & 7)
        for i, obj in enumerate(group):
            self.queue[3 * i : 3 * i + 3] = [obj | side, script & 255, script >> 8]


def main() -> None:
    import game_trace as T

    rom = G.Rom(sys.argv[1])
    frames = T.load(sys.argv[2])
    checked = good = launches = good_launches = set_checked = set_good = parms_good = 0
    shown = 0
    for t in range(1, len(frames)):
        was, now = frames[t - 1], frames[t]
        if not was.byte(T.TASKS + 0x10) or not now.byte(T.TASKS + 0x10):
            continue  # the arcade's attack task is off
        if was.byte(T.ENEMIES_ON) and (not was.byte(T.TASKS + 0x15) or was.byte(T.TASKS + 0x1D)):
            continue  # held: the fighter is not in play
        d = Dives(
            rom, list(was.mem(T.PARMS, 10)), list(was.mem(T.DIVE_TIMERS, 3)), list(was.mem(T.DIVE_TIMERS + 4, 3)),
            list(was.mem(T.BOSS_POOL, 12)), was.byte(T.PARMS + 4), was.byte(T.DIVE_TIMERS + 8),
            was.byte(T.CAPTURING), was.byte(T.CAPTURE_BOSS), was.byte(T.BOSS_TOGGLE), was.byte(T.SPECIAL),
        )  # fmt: skip
        state = {obj: was.state(obj) for obj in range(0, 0x80, 2)}
        free = any(not was.slot(i)[0x13] & 1 for i in range(12))
        go = d.tick(now.byte(T.FRAME), state, now.byte(T.FLYING), free)
        new = [now.slot(i) for i in range(12) if now.slot(i)[0x13] & 1 and not was.slot(i)[0x13] & 1]
        new = [s for s in new if (s[8] | s[9] << 8) in (BEE_DIVE, BUTTERFLY_DIVE, BOSS_DIVE, ROGUE_DIVE, CAPTURE_DIVE)]
        seen = [(s[0x10], s[8] | s[9] << 8, bool(s[0x13] & 0x80)) for s in new]
        want = [(go.obj, go.script, go.mirror)] if go else []
        same_state = (
            bytes(d.timers) == now.mem(T.DIVE_TIMERS, 3)
            and bytes(d.queue) == now.mem(T.BOSS_POOL, 12)
            and d.toggle == now.byte(T.BOSS_TOGGLE)
        )
        checked += 1
        good += same_state and want == seen
        launches += bool(seen or want)
        good_launches += bool(seen) and want == seen
        if not (same_state and want == seen) and shown < 8:
            shown += 1
            print(f"frame {t} (counter {now.byte(T.FRAME)}): model {want} {bytes(d.timers).hex()} {bytes(d.queue).hex()}")
            print(f"    arcade {seen} {now.mem(T.DIVE_TIMERS, 3).hex()} {now.mem(T.BOSS_POOL, 12).hex()}")
        # the restart values and limits the arcade works out every frame
        d.settings(now.byte(T.GAME_TIMERS + 2), now.byte(T.ALIVE), bool(now.byte(T.LAST_STAND)))
        set_checked += 1
        set_good += (
            bytes(d.reload) == now.mem(T.DIVE_TIMERS + 4, 3)
            and d.bomb_flags == now.byte(T.DIVE_TIMERS + 8)
            and d.max_flying == now.byte(T.PARMS + 4)
        )
        parms_good += d.parms == stage_parms(rom, now.byte(T.STAGE))
    print(f"dive scheduler: {checked} frames, {good} as the arcade; {launches} launches, {good_launches} as the arcade")
    print(f"  timer restart values, bomb flags and flying limit: {set_good} of {set_checked} frames as the arcade")
    print(f"  stage settings from the ROM table: {parms_good} of {set_checked} frames as the arcade")


if __name__ == "__main__":
    main()
