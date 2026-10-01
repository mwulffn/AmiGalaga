"""Check the game's stage entrance against the models.

    python3 stagetest.py check galaga.zip results fifths frames

A STAGE_TEST build logs every launch, landing and departure with the frame
it happened in, and a checksum of the formation's positions every frame.
This replays the same frames with the launcher, formation and dive models
(motion/waves.py, formation.py and dives.py, all checked against MAME) and
the flight model (motion/pal_scale.py), following src/game.s step for step,
and compares.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "motion"))
import dives as D  # noqa: E402
import formation as F  # noqa: E402
import galaga_motion as G  # noqa: E402
import pal_scale as P  # noqa: E402
import waves as W  # noqa: E402

SLOTS, FORM_ROWS, STAGE_PAUSE, EMPTY_PAUSE, DEMO_STAGES = 12, 5, 1500, 100, 3  # as in the game's sources
SHIP_START, SHIP_MAX, SHIP_STEP, FIGHTER_X = 104, 208, 2, 17
LAUNCHED, HOME, GONE, FORMATION = 0, 1, 2, 3
NAMES = {LAUNCHED: "launch", HOME: "home", GONE: "gone", FORMATION: "formation"}


def model(rom: G.Rom, fifths: int, frames: int) -> list[tuple[int, int, int]]:
    """(frame, event, object or checksum) for every launch, landing, departure and frame."""
    log = []
    env = P.formation_env()
    slots: list[P.State | None] = [None] * SLOTS
    landed = [False] * SLOTS
    clock, arcade, form_next = 0, 0, 0
    ship, ship_step = SHIP_START, SHIP_STEP
    row_of = lambda obj: (rom.sub[G.HOME_RC + obj] - 22) // 2  # noqa: E731

    def start(stage: int) -> tuple:
        parms = D.stage_parms(rom, stage)
        dives = D.Dives(rom, parms, max_flying=parms[4], capturing=1, special=0xFF)
        env.stage_parms = bytes(parms) + b"\0"
        return stage, W.Launcher(rom, stage), F.Formation(rom), dives, parms

    stage, launcher, form, dives, parms = start(1)
    present: set[int] = set()
    dirty: set[int] = set()
    wait, alive, stage_time = 0, 0, D.STAGE_TIME
    for frame in range(frames):
        ship += ship_step
        if not 0 <= ship <= SHIP_MAX:
            ship_step = -ship_step
            ship += ship_step
        env.fighter_x = env.fighter_x_hw = (ship + FIGHTER_X) & 0xFF
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
                    row, col = rom.sub[G.HOME_RC + go.obj : G.HOME_RC + go.obj + 2]
                    slots[free] = P.State(
                        y=(352 - env.home_x[row]) << 7, x=env.home_x[col] << 7, h=1 << 30, ptr=go.script,
                        obj=go.obj, mirror=go.mirror, left=clock, pause=True,
                    )  # fmt: skip
                    present.discard(go.obj)
                    dirty.add(row_of(go.obj))
                    log.append((frame, LAUNCHED, go.obj))
            form.tick(arcade, launcher.all_in, not present)
            env.home_loc, env.home_x = form.home_loc, form.home_x
            arcade += 1
            clock += 5
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
        busy = sum(s is not None for s in slots)
        rows = dirty or {form_next}
        if not dirty:
            form_next = (form_next + 1) % FORM_ROWS
        for i, st in enumerate(slots):
            if st is not None and landed[i] and row_of(st.obj) in rows:
                present.add(st.obj)
                slots[i], landed[i] = None, False
        dirty = set()
        if launcher.all_in:
            wait += 1
            if wait >= (STAGE_PAUSE if present or busy else EMPTY_PAUSE):
                stage, launcher, form, dives, parms = start(stage % DEMO_STAGES + 1)
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
    counts = ", ".join(f"{sum(e[1] == k for e in want)} {n}" for k, n in NAMES.items())
    print(f"stage entrance, {build}: {frames} frames, model has {len(want)} events ({counts})")
    print(f"  {same} identical in the game's log of {len(got)}")
    if got != want:
        at = next((i for i, (g, w) in enumerate(zip(got, want)) if g != w), min(len(got), len(want)))
        for name, log in (("model", want), ("game", got)):
            print(f"  {name} from event {at}: " + ", ".join(f"{f}:{NAMES.get(e, e)} {o:02x}" for f, e, o in log[at : at + 6]))
        sys.exit(1)


if __name__ == "__main__":
    main()
