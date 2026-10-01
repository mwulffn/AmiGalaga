"""Check the game's stage entrance against the models.

    python3 stagetest.py check galaga.zip results fifths frames

A STAGE_TEST build plays itself (the fighter goes from side to side and
fires every 16 frames) and logs every launch, landing and departure, every
enemy hit or destroyed and the score after it, with the frame it happened
in, and a checksum of the formation's positions every frame. This replays
the same frames with the launcher, formation, dive and shot models
(motion/waves.py, formation.py, dives.py and shots.py, all checked against
MAME) and the flight model (motion/pal_scale.py), following src/game.s step
for step, and compares.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "motion"))
import dives as D  # noqa: E402
import formation as F  # noqa: E402
import galaga_motion as G  # noqa: E402
import pal_scale as P  # noqa: E402
import shots as S  # noqa: E402
import waves as W  # noqa: E402

SLOTS, FORM_ROWS, BLASTS, STAGE_GAP = 12, 5, 8, 100  # as in the game's sources
SHIP_START, SHIP_SX, SHIP_SY, SHIP_LEFT, SHIP_RIGHT = 104, 17, 297, 0x12, 0xE1
AUTO_FIRE, SHOT_GAP, BLAST_STEPS, POPUP_STEPS = 16, 9, 6, 19
LAUNCHED, HOME, GONE, FORMATION, KILLED, BOSS_HIT, SCORE_HI, SCORE_LO = range(8)
NAMES = {
    LAUNCHED: "launch", HOME: "home", GONE: "gone", FORMATION: "formation",
    KILLED: "destroyed", BOSS_HIT: "boss hit", SCORE_HI: "score", SCORE_LO: "score",
}  # fmt: skip


def bcd(n: int) -> int:
    return (n // 10 % 10) << 4 | n % 10


def model(rom: G.Rom, fifths: int, frames: int) -> list[tuple[int, int, int]]:
    """(frame, event, object or value) for everything the game logs."""
    log = []
    env = P.formation_env()
    slots: list[P.State | None] = [None] * SLOTS
    landed = [False] * SLOTS
    clock, arcade, form_next = 0, 0, 0
    ship, pad_right, move_flag, fire_pending = SHIP_START, True, 0, False
    shots = [[0, 0], [0, 0]]  # sprite x, y; x = 0: not in flight
    blasts: list[list[int]] = []  # object, step, pop-up
    score = 0
    rc = lambda obj: rom.sub[G.HOME_RC + obj : G.HOME_RC + obj + 2]  # noqa: E731
    row_of = lambda obj: (rc(obj)[0] - 22) // 2  # noqa: E731
    at = {(row_of(obj), rc(obj)[1] // 2): obj for obj in range(0, 0x60, 2) if rc(obj)[0] >= 22}

    def start(stage: int) -> tuple:
        parms = D.stage_parms(rom, stage)
        dives = D.Dives(rom, parms, max_flying=parms[4], capturing=1, special=0xFF)
        env.stage_parms = bytes(parms) + b"\0"
        return stage, W.Launcher(rom, stage), F.Formation(rom), dives, parms, S.colours(stage)

    stage, launcher, form, dives, parms, colour = start(1)
    present: set[int] = set()
    dirty: set[int] = set()
    wait, alive, stage_time = 0, 0, D.STAGE_TIME

    def place(i: int) -> tuple[int, int]:
        """Where flight i is, as sprite x and y less the buffer's offsets (src/game.s FlightPlace)."""
        st = slots[i]
        row, col = rc(st.obj)
        if landed[i]:
            return env.home_x[col] - 1, env.home_x[row] - 40
        x, y = st.x >> 7, 312 - (st.y >> 7)
        if st.homing:
            off = env.home_loc[row]
            x, y = (x & ~0xFF) | ((x + env.home_loc[col]) & 0xFF), y + (off - 256 if off & 0x80 else off)
        return (x & 0xFF) - 1, y

    def destroy(obj: int, flying: bool) -> None:
        nonlocal score, alive
        points = S.POINTS[colour[obj]]
        score += points * (2 if flying else 1)
        popup = -1
        if flying and colour[obj] == S.BLUE_BOSS:
            popup = dives.bonus[(obj & 7) >> 1]
            score += S.BOSS_BONUS[popup]
        alive -= 1
        log.extend([(frame, KILLED, obj), (frame, SCORE_HI, bcd(score // 100)), (frame, SCORE_LO, bcd(score))])
        if len(blasts) < BLASTS:
            blasts.append([obj, 0, popup])

    def struck(obj: int) -> bool:
        """A hit on obj: True if that destroys it; a boss's first hit only changes its colour."""
        if colour[obj] == S.GREEN_BOSS:
            colour[obj] = S.BLUE_BOSS
            log.append((frame, BOSS_HIT, obj))
            return False
        return True

    for frame in range(frames):
        env.fighter_x = env.fighter_x_hw = (ship + SHIP_SX) & 0xFF
        # the test build plays itself (src/player.s PlayerInput)
        if ship + SHIP_SX >= SHIP_RIGHT:
            pad_right = False
        if ship + SHIP_SX < SHIP_LEFT:
            pad_right = True
        if frame % AUTO_FIRE == 0:
            fire_pending = True
        ticks = 0
        while clock < fifths:
            flying = sum(s is not None and not landed[i] for i, s in enumerate(slots))
            free = next((i for i, s in enumerate(slots) if s is None), None)
            go = launcher.tick(arcade, flying, free is not None)
            if go:
                y, x, head = go.start
                slots[free] = P.State(
                    y=y << 8, x=x << 8, h=head << 30 & 0xFFFFFFFF, ptr=go.script,
                    obj=go.obj, mirror=go.mirror, left=clock, pause=True,
                )  # fmt: skip
                alive += 1
                log.append((frame, LAUNCHED, go.obj))
            if arcade & 31 == 0 and stage_time:
                stage_time -= 1
            env.last_stand = int(alive < parms[7])
            dives.settings(stage_time, alive, bool(env.last_stand))
            if launcher.all_in:
                state = {obj: int(obj in present) for obj in range(0, 0x80, 2)}
                free = next((i for i, s in enumerate(slots) if s is None), None)
                go = dives.tick(arcade, state, launcher.heard, free is not None)
                if go:
                    row, col = rc(go.obj)
                    slots[free] = P.State(
                        y=(352 - env.home_x[row]) << 7, x=env.home_x[col] << 7, h=1 << 30, ptr=go.script,
                        obj=go.obj, mirror=go.mirror, left=clock, pause=True,
                    )  # fmt: skip
                    present.discard(go.obj)
                    dirty.add(row_of(go.obj))
                    log.append((frame, LAUNCHED, go.obj))
            form.tick(arcade, launcher.all_in, not present)
            env.home_loc, env.home_x = form.home_loc, form.home_x
            # the fighter: a pixel and two pixels on alternate frames, then a waiting press fires
            sx = ship + SHIP_SX
            step, move_flag = 1 + move_flag, move_flag ^ 1
            if pad_right and sx < SHIP_RIGHT:
                sx += step
            elif not pad_right and sx >= SHIP_LEFT:
                sx -= step
            ship = sx - SHIP_SX
            if fire_pending:
                mine, other = (shots[0], shots[1]) if not shots[0][0] else (shots[1], shots[0])
                if mine[0]:
                    fire_pending = False  # both in flight: the press is lost
                elif not other[0] or SHIP_SY - other[1] >= SHOT_GAP:
                    mine[0], mine[1], fire_pending = sx, SHIP_SY, False
            for blast in list(blasts):
                if arcade & 3 == (3 if blast[0] & 2 else 1):
                    blast[1] += 1
                    if (blast[1] == BLAST_STEPS and blast[2] < 0) or blast[1] == BLAST_STEPS + POPUP_STEPS:
                        blasts.remove(blast)
            arcade += 1
            clock += 5
            ticks += 1
        clock -= fifths
        check = 0
        for i in range(0, 32, 2):
            check = ((check << 1 | check >> 7) + env.home_x[i]) & 0xFF
        log.append((frame, FORMATION, check))
        env.frame = frame
        for i, st in enumerate(slots):
            if st is None or landed[i]:
                continue
            event = P.frame(st, rom, env, fifths)
            if event == "home":
                landed[i] = True
                log.append((frame, HOME, st.obj))
            elif event == "end":
                slots[i] = None
                log.append((frame, GONE, st.obj))
                if st.obj >= 0x08 and st.obj & 0x38 != 0x38:
                    alive -= 1
        for _ in range(ticks):  # the shots move and hit once for each arcade frame
            for shot in shots:
                if not shot[0]:
                    continue
                shot[1] -= S.SPEED
                if shot[1] < S.TOP:
                    shot[0] = 0
                    continue
                hit = False
                for row in reversed(range(FORM_ROWS)):
                    for col in reversed(range(10)):
                        obj = at.get((row, col))
                        if obj in present and S.hits(env.home_x[2 * col], env.home_x[22 + 2 * row], *shot):
                            hit = True
                            dirty.add(row)
                            if struck(obj):
                                present.discard(obj)
                                destroy(obj, False)
                for i, st in enumerate(slots):
                    if st is None:
                        continue
                    x, y = place(i)
                    if S.hits(x + 1, (y + 40) & 0x1FF, *shot):
                        hit = True
                        if struck(st.obj):
                            was_flying, slots[i], landed[i] = not landed[i], None, False
                            destroy(st.obj, was_flying)
                if hit:
                    shot[0] = 0
        busy = sum(s is not None for s in slots)
        rows = dirty or {form_next}
        if not dirty:
            form_next = (form_next + 1) % FORM_ROWS
        for i, st in enumerate(slots):
            if st is not None and landed[i] and row_of(st.obj) in rows:
                present.add(st.obj)
                slots[i], landed[i] = None, False
        dirty = set()
        if launcher.all_in and not alive and not blasts and not busy:
            wait += 1
            if wait >= STAGE_GAP:
                stage, launcher, form, dives, parms, colour = start(stage + 1)
                present, wait, alive, stage_time = set(), 0, 0, D.STAGE_TIME
                slots, landed = [None] * SLOTS, [False] * SLOTS
                env.home_loc, env.home_x = form.home_loc, form.home_x
    return log


def main() -> None:
    rom = G.Rom(sys.argv[2])
    data = Path(sys.argv[3]).read_bytes()
    fifths, frames = int(sys.argv[4]), int(sys.argv[5])
    got = [(int.from_bytes(data[i : i + 2], "big"), data[i + 2], data[i + 3]) for i in range(0, len(data), 4)]
    want = model(rom, fifths, frames)
    same = sum(g == w for g, w in zip(got, want))
    build = "exact build" if fifths == 5 else "PAL build"
    counts = ", ".join(f"{sum(e[1] == k for e in want)} {n}" for k, n in NAMES.items() if k != SCORE_LO)
    print(f"stage, {build}: {frames} frames, model has {len(want)} events ({counts})")
    print(f"  {same} identical in the game's log of {len(got)}")
    if got != want:
        at = next((i for i, (g, w) in enumerate(zip(got, want)) if g != w), min(len(got), len(want)))
        for name, log in (("model", want), ("game", got)):
            print(f"  {name} from event {at}: " + ", ".join(f"{f}:{NAMES.get(e, e)} {o:02x}" for f, e, o in log[at : at + 6]))
        sys.exit(1)


if __name__ == "__main__":
    main()
