"""Check the game's stage entrance against the models.

    python3 stagetest.py check galaga.zip results fifths frames

A STAGE_TEST build logs every launch, landing and departure with the frame
it happened in. This replays the same frames with the launcher model
(motion/waves.py, checked against MAME) and the flight model
(motion/pal_scale.py), following src/game.s step for step, and compares.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "motion"))
import galaga_motion as G  # noqa: E402
import pal_scale as P  # noqa: E402
import waves as W  # noqa: E402

SLOTS, FORM_ROWS, STAGE_PAUSE, DEMO_STAGES = 12, 5, 150, 3  # as in the game's sources
SHIP_START, SHIP_MAX, SHIP_STEP, FIGHTER_X = 104, 208, 2, 17
LAUNCHED, HOME, GONE = 0, 1, 2
NAMES = {LAUNCHED: "launch", HOME: "home", GONE: "gone"}


def model(rom: G.Rom, fifths: int, frames: int) -> list[tuple[int, int, int]]:
    """(frame, event, object) for every launch, landing and departure."""
    log = []
    env = P.formation_env()
    slots: list[P.State | None] = [None] * SLOTS
    landed = [False] * SLOTS
    stage, clock, arcade, form_next, wait = 1, 0, 0, 0, 0
    ship, ship_step = SHIP_START, SHIP_STEP
    launcher = W.Launcher(rom, stage)
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
                log.append((frame, LAUNCHED, go.obj))
            arcade += 1
            clock += 5
        clock -= fifths
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
        for i, st in enumerate(slots):
            if st is not None and landed[i] and (rom.sub[G.HOME_RC + st.obj] - 22) // 2 == form_next:
                slots[i], landed[i] = None, False
        form_next = (form_next + 1) % FORM_ROWS
        if launcher.done() and not busy:
            wait += 1
            if wait == STAGE_PAUSE:
                stage = stage % DEMO_STAGES + 1
                launcher, wait = W.Launcher(rom, stage), 0
                slots, landed = [None] * SLOTS, [False] * SLOTS
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
