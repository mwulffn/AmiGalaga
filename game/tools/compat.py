"""Try the released disk on other Amigas than the one it is made for.

    tools/compat.py [machine ...]

The game's target is a stock A500 with Kickstart 1.3, but a disk that is given out
is put in whatever its owner has. Each machine here boots the disk (build/galaga.adf)
in an emulator, and the game is played for half a minute by a stick that goes from
side to side and fires. What is checked:

- nothing crashes, the title comes, a game starts and its fighter comes into play;
- the title's picture is, pixel for pixel, the stock A500's;
- the game keeps its speed: 1.2 arcade frames a displayed frame, which it does not
  if frames are late, and the sound driver its 121 ticks a second;
- enemies are hit and sound is heard;
- the left mouse button ends the game, and it starts again from the prompt.

The table says what each machine did. Screenshots of the title and the game are in
build/compat, a directory a machine, for the eye.
"""

import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

from amiga import STOCK_A500, Machine, pin_warning
from game import GAME, Game

WORK = GAME / "build/compat"
PLAY_FRAMES = 1500
# the title's picture is taken when the game has counted this many frames, and on the
# two frames after: how far the game's count is behind the emulator's is a matter of
# how fast the CPU gets to the vertical blank, so a machine's three are compared with
# the stock A500's three, and one in common will do
TITLE_AT = 150
TITLE_PICTURES = 3
SPEED = 60  # arcade frames a second: 1.2 a displayed frame at 50 Hz
TICKS = 121.2  # sound driver ticks a second

STOCK = (("chipmem_size", "1"), ("bogomem_size", "0"))
SLOW = (("chipmem_size", "1"), ("bogomem_size", "2"))
MACHINES = {
    "A500 1.3 512K": STOCK_A500,
    "A500 1.3 +512K slow": Machine("A500,0", "kick34005.A500", SLOW),
    "A500 1.3 +1M fast": Machine(
        "A500,0", "kick34005.A500", (*STOCK, ("fastmem_size", "1"))
    ),
    "A500 1.2 512K": Machine("A500,0", "kick33180.A500", STOCK),
    "A500 2.04 +512K slow": Machine("A500,0", "kick37175.A500", SLOW),
    "A500+ 2.04": Machine("A500+,0", "kick37175.A500"),
    "A600 2.05": Machine("A600,0", "kick37350.A600"),
    "A600 3.1": Machine("A600,0", "kick40063.A600"),
    "A1200 3.0": Machine("A1200,0", "kick39106.A1200"),
    "A1200 3.1": Machine("A1200,0", "kick40068.A1200"),
    "A1200 3.1 +4M fast": Machine(
        "A1200,0", "kick40068.A1200", (("fastmem_size", "4"),)
    ),
    "A4000 3.1": Machine("A4000,0", "kick40068.A4000"),
    "A500 1.3 512K NTSC": Machine(
        "A500,0", "kick34005.A500", (*STOCK, ("ntsc", "true"))
    ),
}


@dataclass
class Trial:
    """What one machine did."""

    name: str
    notes: list[str] = field(default_factory=list)
    title: list[int] = field(default_factory=list)  # checksums of the title's pictures
    failed: str = ""
    seconds: float = 0.0


def pictures(game: Game, name: str, count: int = 1) -> list[int]:
    """Save the picture, and return a checksum of the pixels of it and of as many
    frames after it as make `count`."""
    path = (game.work / f"{name}.png").resolve()
    return game.amiga.lua(
        "emu.warp(false) emu.wait_frames(4) "
        f"video.screenshot({str(path)!r}) local sums = {{}} "
        f"for frame = 1, {count} do local pixels = video.pixels() local sum = 0 "
        "for i = 1, #pixels do sum = (sum * 31 + pixels:byte(i)) % 4294967296 end "
        "sums[frame] = sum emu.wait_frames(1) end emu.warp(true) return sums"
    )[0]


def play(game: Game, frames: int) -> None:
    """The stick from side to side, a second each way, and the button now and then."""
    game.amiga.lua(
        f"for frame = 0, {frames - 1} do "
        "local right = frame % 100 < 50 "
        "input.joy(1, 'right', right) input.joy(1, 'left', not right) "
        "input.joy(1, 'fire', frame % 16 < 2) emu.wait_frames(1) end "
        "for _, button in ipairs({'left', 'right', 'fire'}) do "
        "input.joy(1, button, false) end"
    )
    game.wait(0)  # raises if the program crashed meanwhile


def trial(name: str) -> Trial:
    """Boot the disk on one machine and play."""
    result = Trial(name)
    start = time.monotonic()
    work = WORK / "".join(c if c.isalnum() else "-" for c in name).lower()
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    adf = work / "galaga.adf"
    shutil.copy(GAME / "build/galaga.adf", adf)
    try:
        with Game(work, MACHINES[name], floppy=adf, hard_drive=False) as game:
            timing = game.amiga.lua("return emu.timing()")[0]
            result.notes.append(f"{timing['lines']} lines at {timing['hz']:.1f} Hz")
            game.wait_for("FrameCount", TITLE_AT, 2 * TITLE_AT, 2)
            result.title = pictures(game, "title", TITLE_PICTURES)
            width, height = game.amiga.lua("return video.size()")
            result.notes.append(f"picture {width}x{height}")

            game.press("fire")
            game.wait_for("InPlay", 0, 2000, differs=True)
            game.set("Lives", 5)  # so the game outlasts the test
            game.listen()
            game.amiga.lua(
                "ticks = 0 tick_point = dbg.bpset('SoundInterrupt', "
                "function() ticks = ticks + 1 end)"
            )
            before = [game.get("ArcadeFrame", 2), game.get("FrameCount", 2)]
            play(game, PLAY_FRAMES)
            arcade = (game.get("ArcadeFrame", 2) - before[0]) % 65536
            shown = (game.get("FrameCount", 2) - before[1]) % 65536
            ticks = game.amiga.lua("dbg.bpclear(tick_point) return ticks")[0]
            pictures(game, "game")
            seconds = shown / timing["hz"]
            speed, rate = arcade / seconds, ticks / seconds
            result.notes.append(f"{speed:.1f} arcade frames a second")
            result.notes.append(f"{rate:.1f} sound ticks a second")
            result.notes.append(f"score {game.get('Score', 4):06x}")
            problems = []
            if abs(speed - SPEED) > 0.5:
                problems.append("the game's speed")
            if abs(rate - TICKS) > 2:
                problems.append("the sound's speed")
            if game.get("Score", 4) == 0:
                problems.append("nothing hit")
            if game.heard() == 0:
                problems.append("nothing heard")

            game.amiga.lua(
                "input.mouse_button(1, true) emu.wait_frames(5) "
                "input.mouse_button(1, false)"
            )
            game.run_again()
            result.failed = ", ".join(problems)
    except Exception as error:  # noqa: BLE001  whatever went wrong is the result
        result.failed = f"{type(error).__name__}: {error}".splitlines()[0]
    result.seconds = time.monotonic() - start
    return result


def main() -> None:
    if warning := pin_warning():
        print(warning)
    stock = next(iter(MACHINES))
    names = sys.argv[1:] or list(MACHINES)
    if stock not in names:
        names.insert(0, stock)  # what the others are compared with
    with ThreadPoolExecutor() as pool:
        trials = list(pool.map(trial, names))
    bad = 0
    for t in trials:
        if not t.failed and not set(t.title) & set(trials[names.index(stock)].title):
            t.failed = "the title's picture is not the stock A500's"
        bad += bool(t.failed)
        print(f"{t.name:22s}{'FAILED: ' + t.failed if t.failed else 'ok'}")
        print(f"{'':22s}{'; '.join(t.notes)}")
    print(
        f"{len(trials) - bad} of {len(trials)} machines ran the game as the stock A500"
    )
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
