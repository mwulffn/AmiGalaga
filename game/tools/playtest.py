"""Play the released game from outside and check what only a player could before.

Each scene here starts the game in an emulator (game.py), works the stick, the
button and the keyboard, and checks the game's state and what it leaves on disk:
the title and the options, the SHOTS option in a game, the pause key, the attract
mode, entering initials, and saving the best scores to a hard drive directory, to
a floppy and to a floppy that cannot be written. `tools/run_tests.py play` runs
them; each leaves screenshots in its directory under build/tests for the eye.

A scene returns what it wants said about it, and fails with an AssertionError.
"""

import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path

from game import GAME, PROGRAM, Game

# the stress runs: name, what the build is given, shots in flight at once
STRESS = (
    ("stage-1", "", 2),
    ("stage-9", "-DFIRST_STAGE=9", 2),
    ("stage-9-four-shots-two-fighters", "-DFIRST_STAGE=9 -DDUAL_START=1", 4),
    ("stage-14-four-shots-two-fighters", "-DFIRST_STAGE=14 -DDUAL_START=1", 4),
    ("stage-20-four-shots-two-fighters", "-DFIRST_STAGE=20 -DDUAL_START=1", 4),
)

BEAM = 0xDFF006  # vhposr: where the beam is
FILE = "AmiGalaga.scores"
FILE_SIZE = 48  # a mark, five scores, five names, a checksum
GAME_STARTS = 2000  # frames from START GAME to a fighter in play, at most
GAME_ENDS = 40000  # frames a fighter left alone lasts, at most
A_SCORE = 0x00054320
A_LOWER_SCORE = 0x00030000


def expect(what: str, got: object, wanted: object) -> None:
    """Fail the scene unless a value is what it should be."""
    if got != wanted:
        raise AssertionError(f"{what}: {got!r}, expected {wanted!r}")


def start_game(game: Game) -> None:
    """From the title, with the stick on START GAME, to a fighter in play."""
    game.press("fire")
    expect("mode after START GAME", game.get("Mode"), game.v["MODE_GAME"])
    game.wait_for("InPlay", 0, GAME_STARTS, differs=True)


def shots_in_flight(game: Game, frames: int) -> int:
    """Hammer the button for a while: the most shots in flight at once."""
    shots, size = game.address("Shots"), game.v["sh_SIZEOF"]
    return game.amiga.lua(
        f"local most = 0 for frame = 1, {frames} do "
        f"input.joy(1, 'fire', frame % 2 == 0) emu.wait_frames(1) local n = 0 "
        f"for i = 0, {game.v['MAX_SHOTS'] - 1} do "
        f"if mem.peek_u16({shots} + i * {size}) ~= 0 then n = n + 1 end end "
        "if n > most then most = n end end input.joy(1, 'fire', false) return most"
    )[0]


def menus(work: Path) -> list[str]:
    """The title's lines, every option, and a game started with what was chosen."""
    with Game(work) as game:
        v = game.v
        for direction, item in (("down", 1), ("down", 2), ("down", 0), ("up", 2)):
            game.press(direction)
            expect(f"title line after {direction}", game.get("MenuItem"), item)
        game.press("up")
        game.press("fire")
        expect("mode after OPTIONS", game.get("Mode"), v["MODE_OPTIONS"])

        expect("fighters at first", game.get("OptLives"), v["RESERVE"])
        game.press("right")
        expect("fighters changed", game.get("OptLives"), v["RESERVE_MORE"])
        game.press("fire")
        expect("fighters changed back", game.get("OptLives"), v["RESERVE"])
        game.press("left")
        expect("fighters changed again", game.get("OptLives"), v["RESERVE_MORE"])

        game.press("down")
        # easy is the arcade's switch value 3, then 0, 1 and 2
        for direction, option, rank in (
            ("right", 1, 0),
            ("right", 2, 1),
            ("right", 3, 2),
            ("right", 0, 3),
            ("left", 3, 2),
            ("left", 2, 1),
        ):
            game.press(direction)
            expect(f"difficulty after {direction}", game.get("OptRank"), option)
            expect(f"rank after {direction}", game.get("Rank"), rank)

        game.press("down")
        expect("shots at first", game.get("OptShots"), v["SHOTS"])
        for direction, shots in (("right", 3), ("right", 4), ("right", 2), ("left", 4)):
            game.press(direction)
            expect(f"shots after {direction}", game.get("OptShots"), shots)
        game.screenshot("options")

        game.press("down")
        game.press("left")  # nothing on BACK but the button
        expect("mode on BACK", game.get("Mode"), v["MODE_OPTIONS"])
        game.press("fire")
        expect("mode after BACK", game.get("Mode"), v["MODE_TITLE"])
        expect("title line after BACK", game.get("MenuItem"), 0)

        start_game(game)
        expect("fighters in reserve", game.get("Lives"), v["RESERVE_MORE"])
        expect("rank in the game", game.get("Rank"), 1)
        most = shots_in_flight(game, 150)
        game.screenshot("four-shots")
        expect("most shots in flight with SHOTS at 4", most, 4)
    return ["six fighters, HARD and four shots chosen, and the game has them"]


def pause(work: Path) -> list[str]:
    """P holds a game and lets it go; no other key does, and not on the title."""
    with Game(work) as game:
        game.key("p")
        expect("paused on the title", game.get("Paused"), 0)
        start_game(game)
        game.listen()
        expect("most shots in flight as the game comes", shots_in_flight(game, 150), 2)
        if not game.heard():
            raise AssertionError("nothing heard in a game: the check would say nothing")

        for key in ("a", "space", "o", "return"):
            game.key(key)
            expect(f"paused by {key}", game.get("Paused"), 0)
        game.key("p")
        expect("paused by P", game.get("Paused") != 0, True)
        game.wait(5)  # the sound driver's last tick
        game.listen()
        before = [game.get(f, 2) for f in ("ArcadeFrame", "ShipX", "StarFirst")]
        game.stick("left", True)
        game.wait(100)
        game.stick("left", False)
        after = [game.get(f, 2) for f in ("ArcadeFrame", "ShipX", "StarFirst")]
        expect("arcade frame, fighter and stars after 100 frames", after, before)
        expect("heard while paused", game.heard(), 0)
        game.screenshot("paused")

        game.key("a")
        expect("still paused after another key", game.get("Paused") != 0, True)
        game.key("p")
        expect("paused after P again", game.get("Paused"), 0)
        game.listen()
        shots_in_flight(game, 100)
        moved = game.get("ArcadeFrame", 2) - before[0]
        expect("the game goes on", moved > 100, True)
        expect("heard again", game.heard() > 0, True)
        # every press counts: the keyboard is answered each time
        for count in range(1, 8):
            game.key("p", 2)
            expect(
                f"paused after {count} more", game.get("Paused") != 0, count % 2 == 1
            )
    return ["P holds the game, the stars and the sound, and lets them go"]


def attract(work: Path) -> list[str]:
    """Left alone: the best scores, then a silent game that the button ends."""
    with Game(work) as game:
        v = game.v
        game.listen()
        to_scores = game.wait_for("Mode", v["MODE_SCORES"], v["TITLE_FRAMES"] + 50)
        game.screenshot("scores")
        to_demo = game.wait_for("Demo", 0, v["SCORES_FRAMES"] + 50, differs=True)
        expect("mode in the attract mode", game.get("Mode"), v["MODE_GAME"])
        expect("fighters in reserve", game.get("Lives"), 0)
        game.wait(600)
        game.screenshot("attract")
        game.key("p")
        expect("paused in the attract mode", game.get("Paused"), 0)
        expect("still the attract mode", game.get("Demo") != 0, True)
        game.press("fire")
        game.wait_for("Mode", v["MODE_TITLE"], 20)
        expect("attract mode over at the button", game.get("Demo"), 0)

        # and once more, to its own end: the fighter lost, or 45 seconds
        game.wait_for(
            "Demo", 0, v["TITLE_FRAMES"] + v["SCORES_FRAMES"] + 100, differs=True
        )
        lasted = game.wait_for("Mode", v["MODE_TITLE"], v["DEMO_FRAMES"] + 500)
        expect("heard from the title to the attract mode's end", game.heard(), 0)
        expect("score after it", game.get("Score", 4), 0)
        expect("high score after it", game.get("HighScore", 4), v["FIRST_SCORE"])
        expect("best score after it", game.get("Scores", 4), v["FIRST_SCORE"])
    return [
        (
            f"best scores after {to_scores} frames, the attract mode {to_demo} later;"
            f" left alone it lasted {lasted} frames"
        )
    ]


def play_to_initials(game: Game, score: int, place: int) -> None:
    """A game with a given score and no fighter in reserve, left until it is over."""
    start_game(game)
    game.set("Score", score, 4)
    game.set("Lives", 0)
    game.wait_for("Mode", game.v["MODE_ENTRY"], GAME_ENDS)
    expect("its place among the best", game.get("EntryPlace"), place)
    expect("its initials at first", game.text(f"Names+{4 * place}", 3), "AAA")


def enter_initials(game: Game) -> str:
    """Choose three initials with the stick. Returns what they should be."""
    game.press("right")
    game.press("right")
    game.press("fire")  # C
    game.stick("right", True)  # held, the letter runs on
    game.wait(100)
    game.stick("right", False)
    game.wait(3)
    second = game.text("Names+1", 1)
    expect("a held stick runs through the letters", "F" <= second <= "Z", True)
    game.screenshot("initials")
    game.press("fire")
    game.press("left")
    game.press("left")  # back from A: a space, then the full stop
    game.press("fire")
    expect("mode after the third", game.get("Mode"), game.v["MODE_SCORES"])
    return f"C{second}."


def quit_game(game: Game) -> None:
    """From the best scores to the title, and QUIT."""
    game.press("fire")
    expect("mode at a touch", game.get("Mode"), game.v["MODE_TITLE"])
    game.press("up")
    expect("title line", game.get("MenuItem"), game.v["ITEM_QUIT"])
    game.press("fire")


def initials(work: Path) -> list[str]:
    """Initials, saving on QUIT to a hard drive directory, and reading them back."""
    shutil.copy(GAME / f"build/{PROGRAM}", work / f"hd/{PROGRAM}")
    file = work / "hd" / FILE
    with Game(work) as game:
        expect("read from disk", game.get("ScoresLoaded"), 0)
        play_to_initials(game, A_SCORE, 0)
        name = enter_initials(game)
        expect("best score", game.get("Scores", 4), A_SCORE)
        expect("its initials", game.text("Names", 3), name)
        expect("second best", game.get("Scores+4", 4), game.v["FIRST_SCORE"])
        quit_game(game)
        game.amiga.wait_for_file(file, FILE_SIZE, 500)
        game.run_again()
        expect("read from disk the second time", game.get("ScoresLoaded") != 0, True)
        expect("its initials the second time", game.text("Names", 3), name)
    expect(
        "the file",
        (len(file.read_bytes()), file.read_bytes()[:4]),
        (FILE_SIZE, b"AGS1"),
    )

    with Game(work) as game:
        expect("read from disk", game.get("ScoresLoaded") != 0, True)
        expect("best score read back", game.get("Scores", 4), A_SCORE)
        expect("its initials read back", game.text("Names", 3), name)
        expect("high score", game.get("HighScore", 4), A_SCORE)
        # a second best, its initials left alone: taken as they are
        play_to_initials(game, A_LOWER_SCORE, 1)
        patience = game.v["ENTRY_FRAMES"]
        took = game.wait_for("Mode", game.v["MODE_SCORES"], patience + patience // 10)
        expect("second best's initials", game.text("Names+4", 3), "AAA")
        expect("best score still", game.text("Names", 3), name)
        game.screenshot("scores")

    damaged = bytearray(file.read_bytes())
    damaged[10] ^= 1
    file.write_bytes(damaged)
    with Game(work) as game:
        expect("a damaged file read", game.get("ScoresLoaded"), 0)
        expect("best score then", game.get("Scores", 4), game.v["FIRST_SCORE"])
    return [
        (
            f"{name} entered, saved and read back; initials left alone are taken after"
            f" {took} frames; a damaged file is ignored"
        )
    ]


def on_floppy(adf: Path) -> bytes | None:
    """The best scores' file on a disk image, or None if it has none."""
    out = adf.with_suffix(".scores")
    out.unlink(missing_ok=True)
    done = subprocess.run(
        ["xdftool", str(adf), "read", FILE, str(out)], capture_output=True, check=False
    )
    return out.read_bytes() if done.returncode == 0 and out.exists() else None


def floppy(work: Path) -> list[str]:
    """The same from the disk the game is given out on, and from one that cannot
    be written: nothing saved then, and no requester in the way."""
    adf = work / f"{PROGRAM}.adf"
    shutil.copy(GAME / f"build/{PROGRAM}.adf", adf)
    with Game(work, floppy=adf) as game:
        expect("read from disk", game.get("ScoresLoaded"), 0)
        play_to_initials(game, A_SCORE, 0)
        name = enter_initials(game)
        quit_game(game)
        game.run_again()
        expect("read from the floppy the second time", game.text("Names", 3), name)
        game.wait(300)  # the drive's own time to write
    saved = on_floppy(adf)
    expect("the file on the floppy", saved is not None and len(saved), FILE_SIZE)
    with Game(work, floppy=adf) as game:
        expect("read from the floppy", game.get("ScoresLoaded") != 0, True)
        expect("its initials read back", game.text("Names", 3), name)

    locked = work / "locked.adf"
    shutil.copy(GAME / f"build/{PROGRAM}.adf", locked)
    locked.chmod(0o444)  # an image that cannot be written is a write-protected disk
    before = locked.read_bytes()
    with Game(work, floppy=locked) as game:
        play_to_initials(game, A_SCORE, 0)
        enter_initials(game)
        quit_game(game)
        game.screenshot("write-protected")
        game.run_again()  # no requester is in the way
        expect("read from disk", game.get("ScoresLoaded"), 0)
    expect("the write-protected image unchanged", locked.read_bytes() == before, True)
    return [f"{name} saved to the floppy and read back; a write-protected one is left"]


def stress(shots: int, passes: int = 6000) -> Callable[[Path], list[str]]:
    """A scene that plays harder than the test builds' player does: the button
    hammered, with `shots` in flight at once, and the fighters in reserve topped up
    so the game lasts. It times every pass of the main loop, from the first thing
    after the wait for the frame to the flip, and counts those that missed a frame,
    which is what a player would see as a hitch; it fails if there are any.
    Which stage it starts at and whether with two fighters is the build's business
    (FIRST_STAGE, DUAL_START).

    The same game is played whatever the code costs, so that two builds can be
    compared: the stick and the button go by the game's own passes, not by the
    emulator's frames, and the beam's position, which the game mixes into its
    random numbers, is read as nought there."""

    def scene(work: Path) -> list[str]:
        with Game(work) as game:
            game.amiga.lua(
                "local random = dbg.symbol('Random') "
                f"still = mem.tap_read({BEAM}, {BEAM + 1}, "
                "function(address, value, size, pc) "
                "if pc >= random and pc < random + 16 then return 0 end end)"
            )
            game.set("OptShots", shots)
            start_game(game)
            first = game.get("Stage", 2)
            count, lives = game.address("FrameCount"), game.address("Lives")
            late, lines = game.amiga.lua(
                f"local done, start, late, lines, last = 0, 0, 0, {{}}, mem.peek_u16({count}) "
                "local began = dbg.bpset('SpritesUpdate', function() "
                "start = emu.cycles() end) "
                "local flip = dbg.bpset('VideoFlip', function() "
                "done = done + 1 lines[done] = (emu.cycles() - start) // 454 "
                f"local now = mem.peek_u16({count}) "
                "if (now - last) % 65536 > 1 then late = late + 1 end last = now "
                "local right = done % 160 < 80 "
                "input.joy(1, 'right', right) input.joy(1, 'left', not right) "
                "input.joy(1, 'fire', done % 2 == 0) "
                f"if done % 500 == 1 then mem.poke_u8({lives}, 9) end end) "
                f"while done < {passes} do emu.wait_frames(10) end "
                "dbg.bpclear(began) dbg.bpclear(flip) mem.tap_remove(still) "
                "return late, lines"
            )
            game.amiga.wait(0)  # raises if the program crashed meanwhile
            lines = sorted(lines[:passes])
            said = (
                f"{shots} shots, stages {first} to {game.get('Stage', 2)}, score"
                f" {game.get('Score', 4):06x}: {late} of {passes} frames late; a frame's"
                f" work {sum(lines) / passes:.1f} lines on average,"
                f" {lines[passes * 99 // 100]} at the 99th hundredth, {lines[-1]} at worst"
            )
            if late:
                raise AssertionError(said)
        return [said]

    return scene


SCENES: dict[str, Callable[[Path], list[str]]] = {
    "menus": menus,
    "pause": pause,
    "attract": attract,
    "initials": initials,
    "floppy": floppy,
}
