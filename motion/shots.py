"""The fighter's shots: what they hit and what it scores, as the arcade does it.

    python3 shots.py path/to/galaga.zip game.bin

Ported from the sub CPU's shot handler ($06F5) and the main CPU's scoring.
A shot climbs 6 lines a frame and is gone above sprite y 40. After it has
moved it hits every enemy whose sprite is within 5 pixels to either side and,
with both y's halved as the arcade does, from 3 above to 2 below. A boss
takes two hits. Points go by the enemy's colour set and double if it was
flying; a boss shot while diving adds a bonus for the escorts it set off with.

With a trace from trace_game.lua, every shot of every frame is tested
against every enemy and the result compared with what the arcade did.
"""

import sys

SPEED, TOP = 6, 40
ASIDE, ABOVE, BELOW = 5, 3, 2
# points by colour set: blue (hit) boss, butterfly, bee, the challenging stages' three, red fighter
POINTS = {1: 150, 2: 80, 3: 50, 4: 80, 5: 80, 6: 80, 7: 500}
BOSS_BONUS = (100, 500, 1300)  # for 0, 1, 2 escorts: 400, 800, 1600 in all when shot diving
GREEN_BOSS, BLUE_BOSS = 0, 1
# colour sets of what a challenging stage's enemies look like, by stage / 4 mod 8
CHALLENGE_COLOURS = (3, 2, 2, 5, 2, 6, 4, 2)


def hits(ox: int, oy: int, sx: int, sy: int) -> bool:
    """Enemy sprite at (ox, oy), shot at (sx, sy) after its move."""
    return (((oy >> 1) - (sy >> 1) + ABOVE) & 0xFF) <= ABOVE + BELOW and ((ox - sx + ASIDE) & 0xFF) <= 2 * ASIDE


def colours(stage: int) -> dict[int, int]:
    """Each object's colour set at the start of a stage."""
    challenge = stage & 3 == 3
    bee, butterfly = (CHALLENGE_COLOURS[(stage >> 2) & 7],) * 2 if challenge else (3, 2)
    out = {obj: bee for obj in range(0x08, 0x30, 2)}
    out.update({obj: GREEN_BOSS for obj in range(0x30, 0x40, 2)})
    out.update({obj: butterfly for obj in range(0x40, 0x60, 2)})
    return out


def main() -> None:
    import game_trace as T

    frames = T.load(sys.argv[2])

    def sprite(f: T.Frame, obj: int) -> tuple[int, int]:
        return f.byte(T.SPRITE_POS + obj), f.byte(T.SPRITE_POS + obj + 1) | (f.byte(T.SPRITE_CTRL + obj + 1) & 1) << 8

    agree = missed = extra = 0
    for t in range(400, len(frames) - 1):
        was, now = frames[t - 1], frames[t]
        for shot in (0x64, 0x66):
            sx, sy = sprite(was, shot)
            if not sx or not sy:
                continue
            gone = sprite(now, shot)[1] == 0  # the arcade zeroes a shot's y when it has hit
            found = any(
                was.state(obj) not in (0x80, 4, 5) and hits(*sprite(now, obj), sx, sy - SPEED)
                for obj in range(0, 0x60, 2)
            )
            agree += gone and found
            missed += gone and not found
            extra += found and not gone
    print(f"shots: {agree} hits where the arcade had one, {missed} of the arcade's not found, {extra} it did not have")


if __name__ == "__main__":
    main()
