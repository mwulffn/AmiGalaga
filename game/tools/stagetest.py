"""Check the game's stage entrance against the models.

    python3 stagetest.py check galaga.zip results fifths frames [first stage]

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
import bombs as B  # noqa: E402
import dives as D  # noqa: E402
import formation as F  # noqa: E402
import galaga_motion as G  # noqa: E402
import pal_scale as P  # noqa: E402
import shots as S  # noqa: E402
import transform as TF  # noqa: E402
import waves as W  # noqa: E402

SLOTS, FORM_ROWS, BLASTS = 12, 5, 8  # as in the game's sources
SHIP_START, SHIP_SX, SHIP_SY, SHIP_LEFT, SHIP_RIGHT = 104, 17, 297, 0x12, 0xE1
AUTO_FIRE, SHOT_GAP, BLAST_STEPS, POPUP_STEPS = 16, 9, 6, 19
LAUNCHED, HOME, GONE, FORMATION, KILLED, BOSS_HIT, SCORE_HI, SCORE_LO, FIGHTER_LOST, BOMB = range(10)
PLAYING, BLOWN, RETURNING, READY, OVER, ABSENT, TAKEN, SHOWN = range(8)  # what the fighter is doing (SHOWN: the results)
PLAY, INTRO, CLEARED, RESULTS, SPLASH, ENTER = range(6)  # where the game is between stages (src/flow.s)
INTRO_PAUSE, CLEARED_PAUSE, SPLASH_PAUSE, RESULT_PAUSE, RESULT_END, BLINKS = 8, 4, 3, 3, 6, 7
WAVE_POINTS, WAVE_POPUPS = (1000, 1500, 2000, 3000), (3, 4, 5, 6)
BEGUN = 10
RESERVE, BLOWN_STEPS, BLOWN_PAUSE, READY_PAUSE, OVER_PAUSE, RETURN_SX, TIME_BACK = 2, 15, 4, 3, 6, 0x7A, 30
RESULTS_PAUSE = 14
NAMES = {
    LAUNCHED: "launch", HOME: "home", GONE: "gone", FORMATION: "formation",
    KILLED: "destroyed", BOSS_HIT: "boss hit", SCORE_HI: "score", SCORE_LO: "score",
    FIGHTER_LOST: "fighter lost", BOMB: "bomb", BEGUN: "stage begun",
}  # fmt: skip


def bcd(n: int) -> int:
    return (n // 10 % 10) << 4 | n % 10


def model(rom: G.Rom, fifths: int, frames: int, first: int = 1) -> list[tuple[int, int, int]]:
    """(frame, event, object or value) for everything the game logs."""
    log = []
    env = P.formation_env()
    slots: list[P.State | None] = [None] * SLOTS
    landed = [False] * SLOTS
    clock, arcade, form_next = 0, 0, 0
    ship, pad_right, move_flag, fire_pending = SHIP_START, True, 0, False
    shots = [[0, 0], [0, 0]]  # sprite x, y; x = 0: not in flight
    blasts: list[list[int]] = []  # object, step, pop-up
    bombs = [[0, 0, 0, 0] for _ in range(B.BOMBS)]  # sprite x (0: free), y, rate, carry
    score = 0
    lives, game_timer, fighter_step, new_game = RESERVE, 0, 0, False
    rc = lambda obj: rom.sub[G.HOME_RC + obj : G.HOME_RC + obj + 2]  # noqa: E731
    row_of = lambda obj: (rc(obj)[0] - 22) // 2  # noqa: E731
    at = {(row_of(obj), rc(obj)[1] // 2): obj for obj in range(0, 0x60, 2) if rc(obj)[0] >= 22}

    rnd = W.Random()
    looks = {"butterfly": 2, "bee": 3, "boss": S.GREEN_BOSS}

    def start(stage: int) -> tuple:
        parms = D.stage_parms(rom, stage)
        dives = D.Dives(rom, parms, max_flying=parms[4], capturing=1, special=0xFF)
        env.stage_parms = bytes(parms) + b"\0"
        row = W.stage_row(rom, stage)
        launcher = W.Launcher(rom, stage, rnd=rnd)
        return stage, launcher, F.Formation(rom), dives, parms, S.colours(stage), row[0], row[1]

    def idle() -> tuple:
        """No stage yet (src/stage.s StageIdle): nothing to launch, the formation empty."""
        launcher = W.Launcher(rom, 1)
        launcher.table = bytes([W.WAVE_END])
        return launcher, F.Formation(rom)

    # a game's opening (src/game.s GameInit, src/flow.s FlowInit)
    stage, parms, colour, bomb_reload, entry_bombs = first - 1, [0] * 10, S.colours(1), 0, 0
    dives = D.Dives(rom, parms, capturing=1, special=0xFF)
    launcher, form = idle()
    present: set[int] = set()
    dirty: set[int] = set()
    alive, stage_time, flying_hits = 0, 0, 0
    tf, tf_armed, trio_left, own_colour = TF.Transform(), False, 0, 0
    result_step = 0
    flow, flow_timer, flow_step, first_stage, next_bonus = INTRO, INTRO_PAUSE, 0, True, 20000
    state, in_play = ABSENT, False

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
        nonlocal flying_hits
        points = S.POINTS[colour[obj]]
        score += points * (2 if flying else 1)
        popup = -1
        nonlocal trio_left
        if flying:
            flying_hits += 1
            launcher.wave_hits = (launcher.wave_hits - 1) & 0xFF
            if not launcher.wave_hits and stage & 3 == 3:  # all eight of a challenging stage's wave
                score += WAVE_POINTS[min(stage >> 3, 3)]
                popup = WAVE_POPUPS[min(stage >> 3, 3)]
            elif obj & 0x38 == 0x38 or obj == dives.special:  # one of a transformed enemy's three
                trio_left = (trio_left - 1) & 0xFF
                if not trio_left:
                    score += TF.BONUS[tf.colour]
                    popup = {1000: 3, 2000: 5, 3000: 6}[TF.BONUS[tf.colour]]
            elif colour[obj] == S.BLUE_BOSS:
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
        if new_game:  # src/game.s GameInit: everything but the clocks and the last stage's settings
            score, ship, pad_right, move_flag, fire_pending = 0, SHIP_START, True, 0, False
            lives, game_timer, fighter_step, new_game = RESERVE, 0, 0, False
            shots, blasts = [[0, 0], [0, 0]], []
            bombs = [[0, 0, 0, 0] for _ in range(B.BOMBS)]
            launcher, form = idle()
            present, dirty, alive, stage = set(), set(), 0, first - 1
            slots, landed = [None] * SLOTS, [False] * SLOTS
            env.home_loc, env.home_x = form.home_loc, form.home_x
            flow, flow_timer, first_stage, next_bonus = INTRO, INTRO_PAUSE, True, 20000
            state, in_play = ABSENT, False
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
            go = launcher.tick(arcade, flying, free is not None, in_play)
            if go:
                y, x, head = go.start
                slots[free] = P.State(
                    y=y << 8, x=x << 8, h=head << 30 & 0xFFFFFFFF, ptr=go.script,
                    obj=go.obj, mirror=go.mirror, left=clock, pause=True,
                    bomb_timer=B.SIDE_TIMER if go.path & 1 else B.ENTRY_TIMER,
                    bomb_bits=entry_bombs if not go.look and B.entry_bomber(rom, go.obj) else 0,
                )  # fmt: skip
                if go.look:  # one that only flies through gets its looks now
                    colour[go.obj] = looks[go.look]
                alive += 1
                log.append((frame, LAUNCHED, go.obj))
            if arcade & 31 == 0 and stage_time:
                stage_time -= 1
            env.last_stand = int(alive < parms[7] and in_play)  # without the fighter they go home
            dives.settings(stage_time, alive, bool(env.last_stand))
            env.bomb_bits = dives.bomb_flags
            if launcher.all_in and in_play:
                in_place = {obj: int(obj in present) for obj in range(0, 0x80, 2)}
                free = next((i for i, s in enumerate(slots) if s is None), None)
                go = dives.tick(arcade, in_place, launcher.heard, free is not None)
                if go:
                    row, col = rc(go.obj)
                    slots[free] = P.State(
                        y=(352 - env.home_x[row]) << 7, x=env.home_x[col] << 7, h=1 << 30, ptr=go.script,
                        obj=go.obj, mirror=go.mirror, left=clock, pause=True,
                        bomb_timer=B.DIVE_TIMER, bomb_bits=dives.bomb_flags,
                    )  # fmt: skip
                    present.discard(go.obj)
                    dirty.add(row_of(go.obj))
                    log.append((frame, LAUNCHED, go.obj))
            # the enemy that transforms (src/transform.s)
            if launcher.all_in and not tf_armed:
                tf.on = tf_armed = True
            go = tf.tick(alive, stage, present.__contains__, in_play)
            if tf.picked:
                dives.special, own_colour = tf.obj, colour[tf.obj]
            free = next((i for i, s in enumerate(slots) if s is None), None)
            if go is not None and free is not None:
                row, col = rc(go)
                slots[free] = P.State(
                    y=(352 - env.home_x[row]) << 7, x=env.home_x[col] << 7, h=1 << 30, ptr=TF.SCRIPTS[tf.colour],
                    obj=go, mirror=bool(go & 2), left=clock, pause=True,
                    bomb_timer=B.DIVE_TIMER, bomb_bits=dives.bomb_flags,
                )  # fmt: skip
                present.discard(go)
                dirty.add(row_of(go))
                colour[go], trio_left = tf.colour, 3
                log.append((frame, LAUNCHED, go))
            form.tick(arcade, launcher.all_in, not present)
            env.home_loc, env.home_x = form.home_loc, form.home_x
            # the fighter (src/player.s PlayerTick)
            if arcade & 31 == 0 and game_timer:
                game_timer -= 1
            if state == ABSENT:
                pass
            elif state == OVER:
                if not game_timer:  # the results show, and the stage is taken away (src/flow.s GameResults)
                    state, game_timer, result_step = SHOWN, RESULTS_PAUSE, 0
            elif state == SHOWN:
                new_game = new_game or not game_timer
            elif state == BLOWN:
                if arcade & 3 == 3 and fighter_step:
                    fighter_step -= 1
                if not game_timer:
                    if lives:
                        lives, state = lives - 1, RETURNING
                    else:
                        state, game_timer = OVER, OVER_PAUSE
            elif state == RETURNING:
                if not launcher.heard:  # the divers are home: the next fighter comes on
                    ship, stage_time = RETURN_SX - SHIP_SX, min(stage_time + TIME_BACK, D.STAGE_TIME)
                    state, game_timer = READY, READY_PAUSE
            else:
                if state == READY and not game_timer:
                    state, in_play = PLAYING, True
                # a pixel and two pixels on alternate frames, then a waiting press fires
                sx = ship + SHIP_SX
                step, move_flag = 1 + move_flag, move_flag ^ 1
                if pad_right and sx < SHIP_RIGHT:
                    sx += step
                elif not pad_right and sx >= SHIP_LEFT:
                    sx -= step
                ship = sx - SHIP_SX
                if not in_play:
                    fire_pending = False
                elif fire_pending:
                    mine, other = (shots[0], shots[1]) if not shots[0][0] else (shots[1], shots[0])
                    if mine[0]:
                        fire_pending = False  # both in flight: the press is lost
                    elif not other[0] or SHIP_SY - other[1] >= SHOT_GAP:
                        mine[0], mine[1], fire_pending = sx, SHIP_SY, False
            # the enemies' bomb timers (src/bombs.s BombsDrop)
            for i, st in enumerate(slots):
                if st is None or landed[i] or st.pause:
                    continue
                st.bomb_timer = (st.bomb_timer - 1) & 0xFF
                if st.bomb_timer:
                    continue
                st.bomb_timer, chance, st.bomb_bits = bomb_reload, st.bomb_bits & 1, st.bomb_bits >> 1
                if not chance or not in_play or st.y >> 8 < B.MIN_HEIGHT:
                    continue
                x, y = place(i)
                x, y = (x + 1) & 0xFF, (y + 40) & 0x1FF
                n = next((n for n, b in enumerate(bombs) if not b[0]), None)
                if n is not None:
                    bombs[n] = [x, y, B.aim(ship + SHIP_SX, x, y, n), 0]
                    log.append((frame, BOMB, bombs[n][2]))
            for blast in list(blasts):
                if arcade & 3 == (3 if blast[0] & 2 else 1):
                    blast[1] += 1
                    if (blast[1] == BLAST_STEPS and blast[2] < 0) or blast[1] == BLAST_STEPS + POPUP_STEPS:
                        blasts.remove(blast)
            # the game's flow (src/flow.s FlowTick)
            if arcade & 31 == 0 and flow_timer:
                flow_timer -= 1
            if score >= next_bonus:  # an extra fighter at 20000, 70000 and every 70000 after
                lives += 1
                next_bonus = 70000 if next_bonus == 20000 else next_bonus + 70000 if next_bonus < 930000 else 10**9
            splash = False
            if flow == PLAY and state == SHOWN:
                if result_step == 0:
                    launcher, form = idle()
                    present, dirty, alive = set(), set(), 0
                    slots, landed = [None] * SLOTS, [False] * SLOTS
                    env.home_loc, env.home_x = form.home_loc, form.home_x
                    blasts = []
                    bombs = [[0, 0, 0, 0] for _ in range(B.BOMBS)]
                result_step = min(result_step + 1, 4)
            elif flow == PLAY:
                if launcher.all_in and not alive and state == PLAYING and not blasts and not any(slots):
                    flow, flow_timer = CLEARED, CLEARED_PAUSE
            elif flow == INTRO:
                splash = not flow_timer
            elif flow == CLEARED:
                if not flow_timer:
                    if stage & 3 == 3:
                        flow, flow_step, flow_timer = RESULTS, 0, RESULT_PAUSE
                    else:
                        splash = True
            elif flow == RESULTS:
                bonus = None
                if 3 <= flow_step < 3 + BLINKS:  # PERFECT blinks, then the special bonus
                    if arcade & 15 == 0:
                        flow_step += 1
                        if flow_step == 3 + BLINKS:
                            bonus = 10000
                elif not flow_timer:
                    flow_timer, was, flow_step = RESULT_PAUSE, flow_step, flow_step + 1
                    if was == 2:
                        flow_step = 3 if flying_hits == 40 else 11
                    elif was == 11:
                        bonus = 100 * flying_hits
                    elif was == 12:
                        splash = True
                if bonus is not None:
                    score += bonus
                    log.extend([(frame, SCORE_HI, bcd(score // 100)), (frame, SCORE_LO, bcd(score))])
                    flow_step, flow_timer = 12, RESULT_END
            elif flow == SPLASH:
                if not flow_timer:  # the stage is set up and begins
                    stage, launcher, form, dives, parms, colour, bomb_reload, entry_bombs = start(stage)
                    launcher.wave_hits = 8 if stage & 3 == 3 else 0
                    present, dirty, alive, stage_time, flying_hits = set(), set(), 0, D.STAGE_TIME, 0
                    tf, tf_armed, trio_left = TF.Transform(), False, 0
                    slots, landed = [None] * SLOTS, [False] * SLOTS
                    env.home_loc, env.home_x = form.home_loc, form.home_x
                    log.append((frame, BEGUN, stage & 0xFF))
                    flow = PLAY
                    if first_stage:  # the fighter comes on (src/player.s PlayerEnter)
                        first_stage, flow = False, ENTER
                        ship, game_timer, state = RETURN_SX - SHIP_SX, READY_PAUSE, READY
            elif state == PLAYING:  # ENTER
                flow = PLAY
            if splash:
                stage, flow, flow_timer = stage + 1, SPLASH, SPLASH_PAUSE
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
            if st.spawn:  # another splits off it: the first idle spare object, in the last free slot
                script, y, x, h = st.spawn
                st.spawn = None
                busy = {s.obj for s in slots if s is not None} | {b[0] for b in blasts}
                obj = next((o for o in TF.EXTRAS if o not in busy), None)
                spot = next((j for j in range(SLOTS - 1, -1, -1) if slots[j] is None), None)
                if obj is not None and spot is not None:
                    slots[spot] = P.State(y=y, x=x, h=h, ptr=script, obj=obj, mirror=st.mirror)
                    colour[obj] = colour[st.obj]
                    alive += 1
                    log.append((frame, LAUNCHED, obj))
            if event == "home":
                landed[i] = True
                log.append((frame, HOME, st.obj))
                if st.obj == dives.special:  # the one that transformed is its old self again
                    colour[st.obj], dives.special = own_colour, 0xFF
            elif event == "end":
                slots[i] = None
                log.append((frame, GONE, st.obj))
                if st.obj >= 0x08:
                    alive -= 1
        for tick in range(ticks):  # the shots move and hit once for each arcade frame
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
            tick_frame = arcade - ticks + tick
            for n, bomb in enumerate(bombs):  # src/bombs.s BombsFall
                if bomb[0]:
                    bomb[0], bomb[1], bomb[3] = B.fall(bomb[0], bomb[1], bomb[2], bomb[3], tick_frame)
                    if tick_frame & 3 == (3 if n & 1 else 1) and B.off_screen(bomb[0], bomb[1]):
                        bomb[0] = 0
            if in_play:  # src/player.s FighterHits
                fx, touched = ship + SHIP_SX, False
                if launcher.all_in:
                    near = [
                        i for i, st in enumerate(slots)
                        if st is not None and not landed[i] and B.touches(place(i)[0] + 1, (place(i)[1] + 40) & 0x1FF, fx, SHIP_SY)
                    ]  # fmt: skip
                    if near:
                        i = min(near, key=lambda i: slots[i].obj)
                        touched = True
                        if struck(slots[i].obj):
                            obj, slots[i] = slots[i].obj, None
                            destroy(obj, True)
                for bomb in bombs:
                    if bomb[0] and B.touches(bomb[0], bomb[1], fx, SHIP_SY):
                        bomb[0], touched = 0, True
                        break
                if touched:
                    state, in_play, fighter_step, game_timer, fire_pending = BLOWN, False, BLOWN_STEPS, BLOWN_PAUSE, False
                    log.append((frame, FIGHTER_LOST, lives))
        rows = dirty or {form_next}
        if not dirty:
            form_next = (form_next + 1) % FORM_ROWS
        for i, st in enumerate(slots):
            if st is not None and landed[i] and row_of(st.obj) in rows:
                present.add(st.obj)
                slots[i], landed[i] = None, False
        dirty = set()
    return log


def main() -> None:
    rom = G.Rom(sys.argv[2])
    data = Path(sys.argv[3]).read_bytes()
    fifths, frames = int(sys.argv[4]), int(sys.argv[5])
    first = int(sys.argv[6]) if len(sys.argv) > 6 else 1
    got = [(int.from_bytes(data[i : i + 2], "big"), data[i + 2], data[i + 3]) for i in range(0, len(data), 4)]
    want = model(rom, fifths, frames, first)
    same = sum(g == w for g, w in zip(got, want))
    build = "exact build" if fifths == 5 else "PAL build"
    counts = ", ".join(f"{sum(e[1] == k for e in want)} {n}" for k, n in NAMES.items() if k != SCORE_LO)
    print(f"from stage {first}, {build}: {frames} frames, model has {len(want)} events ({counts})")
    print(f"  {same} identical in the game's log of {len(got)}")
    if got != want:
        at = next((i for i, (g, w) in enumerate(zip(got, want)) if g != w), min(len(got), len(want)))
        for name, log in (("model", want), ("game", got)):
            print(f"  {name} from event {at}: " + ", ".join(f"{f}:{NAMES.get(e, e)} {o:02x}" for f, e, o in log[at : at + 6]))
        sys.exit(1)


if __name__ == "__main__":
    main()
