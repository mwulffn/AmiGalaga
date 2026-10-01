"""Enemy bombs and what destroys the fighter, as the arcade does it.

    python3 bombs.py path/to/galaga.zip game.bin

Ported from the sub CPU's flight loop ($0D50 on), the main CPU's bomb mover
($1EA4) and the sub CPU's fighter collision task ($05EE).

  - A flying enemy has a bomb timer and up to eight "chances" (a byte of
    bits). When the timer runs out the next bit is shifted out; a set bit
    drops a bomb if the enemy is high enough, the fighter is in play and one
    of the 8 bombs is free. The timer then restarts from the stage's value.
  - A bomb is aimed when dropped: its sideways rate is the fighter's
    distance to the side divided by the height to fall, capped, with a sign.
    It falls 2 and 3 lines on alternate frames and moves sideways by its
    rate / 32 pixels, the remainder carried over.
  - A bomb is gone below sprite y 330 (or past x 244), tested every fourth
    frame.
  - The fighter is destroyed by a bomb, or by an enemy (once the stage's
    waves are in), whose sprite is within 6 pixels to the side and 3 two-line
    steps above or below.

With a trace from trace_game.lua each of these is compared with the arcade.
"""

import sys

import galaga_motion as G

BOMBS = 8
FIRST_BOMB = 0x68  # object numbers $68, $6a ... $76
MIN_HEIGHT = 0x4C  # an enemy lower than this (flight y, two-pixel units) does not bomb
FIGHTER_HALF_Y = 0x95  # the fighter's sprite y, halved
MAX_RATE = 0x60
OFF_X, OFF_TOP, OFF_BOTTOM = 0xF4, 22 >> 1, 330 >> 1
ASIDE, UP_DOWN = 6, 3
ENTRY_BOMBERS = 0x2908  # main ROM: a bit per enemy in object order, set if it may bomb on its way in
ENTRY_TIMER, SIDE_TIMER, DIVE_TIMER = 8, 0x44, 0x1E  # frames to an enemy's first chance to bomb


def entry_bomber(rom: G.Rom, obj: int) -> bool:
    k = (obj - 8) >> 1
    return bool(rom.main[ENTRY_BOMBERS + (k >> 3)] << (k & 7) & 0x80)


def aim(fighter_x: int, x: int, y: int, index: int) -> int:
    """The sideways rate of bomb `index` dropped at sprite (x, y): bit 7 = leftwards."""
    dx = abs(fighter_x - x)
    dy = abs(FIGHTER_HALF_Y - (y >> 1))
    q = G.div16(dx << 8 | (FIRST_BOMB + 2 * index + 1), dy)  # the low byte is whatever was in L
    v = (((q >> 2) + q) & 0xFFFF) >> 2
    return min(v, MAX_RATE) >> 1 | (0x80 if fighter_x < x else 0)


def fall(x: int, y: int, rate: int, carry: int, frame: int) -> tuple[int, int, int]:
    """One frame of a bomb: (x, y, carry)."""
    a = (rate & 0x7E) + carry
    dx = a >> 5
    return (x - dx if rate & 0x80 else x + dx) & 0xFF, (y + 2 + (frame & 1)) & 0x1FF, a & 0x1F


def off_screen(x: int, y: int) -> bool:
    return x >= OFF_X or not OFF_TOP <= y >> 1 < OFF_BOTTOM


def touches(ox: int, oy: int, fx: int, fy: int) -> bool:
    """Something's sprite at (ox, oy) against the fighter's at (fx, fy)."""
    return ((ox - fx + ASIDE) & 0xFF) <= 2 * ASIDE and (((oy >> 1) - (fy >> 1) + UP_DOWN) & 0xFF) <= 2 * UP_DOWN


def main() -> None:
    import game_trace as T

    frames = T.load(sys.argv[2])
    rates, fighter, parked = 0x92B0, 0x62, 0x80

    def sprite(f: T.Frame, obj: int) -> tuple[int, int]:
        return f.byte(T.SPRITE_POS + obj), f.byte(T.SPRITE_POS + obj + 1) | (f.byte(T.SPRITE_CTRL + obj + 1) & 1) << 8

    aimed = aimed_ok = moved = moved_ok = deaths = deaths_ok = false_alarms = 0
    for t in range(400, len(frames) - 1):
        was, now = frames[t - 1], frames[t]
        for n in range(BOMBS):
            obj = FIRST_BOMB + 2 * n
            if now.state(obj) == 6 and was.state(obj) != 6:  # dropped: the arcade copies the enemy's position
                aimed += 1
                x, y = sprite(now, obj)
                # the bomb may already have fallen a frame when the trace sees it
                tries = [(x, y)] + [(x, (y - 2 - (f & 1)) & 0x1FF) for f in (now.byte(T.FRAME), was.byte(T.FRAME))]
                aimed_ok += any(
                    aim(sprite(g, fighter)[0], bx, by, n) == now.byte(rates + 2 * n) for bx, by in tries for g in (now, was)
                )
            elif now.state(obj) == 6 and was.state(obj) == 6 and sprite(was, obj)[0]:
                moved += 1
                want = fall(*sprite(was, obj), was.byte(rates + 2 * n), was.byte(rates + 2 * n + 1), now.byte(T.FRAME))
                moved_ok += want == (*sprite(now, obj), now.byte(rates + 2 * n + 1))
        alive = was.state(fighter) != 8 and was.byte(T.TASKS + 0x15)
        died = now.state(fighter) == 8 and was.state(fighter) != 8
        if not alive and not died:
            continue
        fx, fy = sprite(was, fighter)
        fx = sprite(now, fighter)[0] + (8 if died else 0)  # where it is this frame: the blast is drawn 8 to the left
        waves = was.byte(T.TASKS + 0x08)
        # the arcade tests after everything has moved; a bomb that hits is gone from the
        # trace by then, so work out where it had fallen to
        touch = False
        for n in range(BOMBS):
            obj = FIRST_BOMB + 2 * n
            if was.state(obj) == 6 and sprite(was, obj)[0]:
                x, y, _ = fall(*sprite(was, obj), was.byte(rates + 2 * n), was.byte(rates + 2 * n + 1), now.byte(T.FRAME))
                touch = touch or touches(x, y, fx, fy)
        # while a stage's waves are still arriving only bombs and the fly-through enemies count
        for obj in range(0x38, 0x40, 2) if waves else range(0, 0x60, 2):
            if was.state(obj) not in (parked, 4, 5) and sprite(now, obj)[0]:
                touch = touch or touches(*sprite(now, obj), fx, fy)
        if died:
            deaths += 1
            deaths_ok += touch
        elif touch and frames[t + 1].state(fighter) != 8:
            false_alarms += 1
    print(f"bombs: {aimed_ok} of {aimed} aimed as the arcade's, {moved_ok} of {moved} frames of falling as the arcade's")
    print(f"fighter: {deaths_ok} of {deaths} losses explained by a touch; {false_alarms} touches the arcade let pass")


if __name__ == "__main__":
    main()
