"""The game as it is released, running in an emulator and worked from outside.

A test starts it, moves the stick, presses the button and keys, and reads the
game's state by the names the source has for it. Nothing in the program is there
for the test's sake: it is the build that goes on the disk.

The names come from two places. The program's symbols (build/galaga.dbg: the same
program linked with them left in) say where its state is in the Amiga's memory, and
vasm says what each field's offset and each constant's value is, from the headers.
"""

import re
import subprocess
import tempfile
from pathlib import Path
from typing import Self

from amiga import STOCK_A500, Amiga, Machine

GAME = Path(__file__).resolve().parent.parent
HEADERS = ("config.i", "hw.i", "layout.i", "flight.i", "sound.i", "state.i")
NAME = re.compile(r"^(\w+):?\s+(?:rs\.[bwl]|equ)\s", re.MULTILINE)
CONSTANT = re.compile(r"^\w+\s+equ\s.*$", re.MULTILINE)
ORIGIN = re.compile(r"equ\s+\*")
# source files whose own constants a test wants too: the menus' times and places
SOURCES = ("title.s",)
START_FRAMES = 1500  # Kickstart 1.3 has the program running well within this
JOYSTICK = 1  # the port the game's stick is in
# Paula's four channels' registers; a channel's volume is the word at 8 in its 16
AUDIO_FIRST, AUDIO_LAST, VOLUME = 0xDFF0A0, 0xDFF0DF, 8


def header_values() -> dict[str, int]:
    """Every field offset and constant the headers define, worked out by vasm,
    and the constants the files in SOURCES define for themselves."""
    include, build = GAME / "include", GAME / "build"
    names = [m[1] for h in HEADERS for m in NAME.finditer((include / h).read_text())]
    source = "".join(f'\tinclude\t"{h}"\n' for h in HEADERS)
    for file in SOURCES:
        text = (GAME / "src" / file).read_text()
        # not the ones worked out from where the code is ("*")
        own = "".join(f"{c}\n" for c in CONSTANT.findall(text) if not ORIGIN.search(c))
        source += own
        names += [m[1] for m in NAME.finditer(own)]
    # a name inside a conditional block may not exist in this build
    source += "".join(
        f"\tifd\t{name}\n\tdc.l\t{name}\n\telse\n\tdc.l\t0\n\tendc\n" for name in names
    )
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "values.s").write_text(source)
        out = Path(tmp) / "values.bin"
        subprocess.run(
            ["vasmm68k_mot", "-quiet", "-Fbin", "-m68000", f"-I{include}"]
            + [f"-I{build}", "-o", str(out), str(Path(tmp) / "values.s")],
            check=True,
        )
        data = out.read_bytes()
    return {
        name: int.from_bytes(data[4 * i : 4 * i + 4], "big")
        for i, name in enumerate(names)
    }


class Game:
    """The game running in an emulator. `v` has the headers' offsets and constants."""

    def __init__(
        self,
        work: Path,
        machine: Machine = STOCK_A500,
        *,
        floppy: Path | None = None,
        hard_drive: bool = True,
        symbols: Path | None = None,
    ) -> None:
        self.v = header_values()
        self.work = work
        # the directory work/hd is the hard drive; a floppy, if there is one, boots
        (work / "hd").mkdir(parents=True, exist_ok=True)
        self.amiga = Amiga(
            work,
            machine,
            hard_drive=work / "hd" if hard_drive else None,
            floppy=floppy,
        )
        # a run that has a build of its own has that build's symbols beside it
        own = work / "galaga.dbg"
        default = own if own.exists() else GAME / "build/galaga.dbg"
        self.symbols = (symbols or default).resolve()
        try:
            self.find()
        except Exception:
            self.amiga.stop()
            raise

    def find(self) -> None:
        """Wait for the program to be running and showing its title, and find its
        state. The frame counter in the state must be going: memory left by a run
        before this one would have a title in it too."""
        self.state = self.amiga.lua(
            f"dbg.unload_symbols() dbg.load_symbols({str(self.symbols)!r}, 'galaga', "
            f"{START_FRAMES}) return dbg.symbol('State')"
        )[0]
        count, mode = self.address("FrameCount"), self.address("Mode")
        running = self.amiga.lua(
            f"for i = 1, {START_FRAMES} do local was = mem.peek_u16({count}) "
            f"emu.wait_frames(2) if mem.peek_u16({count}) ~= was and "
            f"mem.peek_u8({mode}) == {self.v['MODE_TITLE']} then return true end end "
            "return false"
        )[0]
        self.amiga.wait(0)  # raises if the program crashed meanwhile
        if not running:
            raise AssertionError(f"no title after {2 * START_FRAMES} frames")

    def run_again(self) -> None:
        """After QUIT: start the program again from the AmigaDOS prompt. That it
        starts says the system had the machine back and was taking commands."""
        self.wait(100)
        self.type("galaga\n")
        self.wait(25)
        self.find()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        self.amiga.stop()

    def address(self, field: str) -> int:
        """Where a field of the state is. "Scores+4" is four bytes into Scores."""
        name, _, more = field.partition("+")
        return self.state + self.v[name] + int(more or 0)

    def get(self, field: str, size: int = 1) -> int:
        """A field of the state: `size` bytes of it, as a number."""
        return self.amiga.lua(f"return mem.peek_u{8 * size}({self.address(field)})")[0]

    def text(self, field: str, length: int) -> str:
        """A field of the state as text."""
        return bytes(
            self.amiga.lua(
                f"local t = {{}} for i = 0, {length - 1} do "
                f"t[#t + 1] = mem.peek_u8({self.address(field)} + i) end return t"
            )[0]
        ).decode("latin-1")

    def set(self, field: str, value: int, size: int = 1) -> None:
        """Change a field of the state: a test's way to a scene that takes long."""
        self.amiga.lua(f"mem.poke_u{8 * size}({self.address(field)}, {value})")

    def wait(self, frames: int) -> None:
        """Let the game run for a number of frames."""
        self.amiga.wait(frames)

    def wait_for(
        self,
        field: str,
        value: int,
        frames: int,
        size: int = 1,
        *,
        differs: bool = False,
    ) -> int:
        """Wait until a field has a value (or, with `differs`, any other).

        Returns how many frames it took; fails the test after `frames` frames.
        """
        took = self.amiga.lua(
            f"for i = 0, {frames} do "
            f"if (mem.peek_u{8 * size}({self.address(field)}) == {value}) "
            f"~= {'true' if differs else 'false'} then return i end "
            "if crash then return -2 end emu.wait_frames(1) end return -1"
        )[0]
        self.amiga.wait(0)  # raises if the program crashed meanwhile
        if took < 0:
            now = self.get(field, size)
            raise AssertionError(
                f"{field} is {now} after {frames} frames: expected"
                f" {'anything but ' if differs else ''}{value}"
            )
        return took

    def stick(self, direction: str, down: bool) -> None:
        """Hold the stick ("left", "right", "up", "down") or the button ("fire")."""
        self.amiga.lua(
            f"input.joy({JOYSTICK}, {direction!r}, {'true' if down else 'false'})"
        )

    def press(self, direction: str, frames: int = 3) -> None:
        """Move the stick (or press the button) and let go again."""
        self.amiga.lua(
            f"input.joy({JOYSTICK}, {direction!r}, true) emu.wait_frames({frames}) "
            f"input.joy({JOYSTICK}, {direction!r}, false) emu.wait_frames({frames})"
        )

    def key(self, name: str, frames: int = 3) -> None:
        """Press a key of the keyboard and let go again."""
        self.amiga.lua(
            f"input.key({name!r}, true) emu.wait_frames({frames}) "
            f"input.key({name!r}, false) emu.wait_frames({frames})"
        )

    def listen(self) -> None:
        """Start counting what the game lets be heard: see `heard`."""
        self.amiga.lua(
            "heard = 0 if not listening then listening = mem.tap_write("
            f"{AUDIO_FIRST}, {AUDIO_LAST}, function(address, value) "
            f"if address % 16 == {VOLUME} and value % 128 ~= 0 then heard = heard + 1 "
            "end end) end"
        )

    def heard(self) -> int:
        """How many times a sound channel was given a volume above nought since
        `listen`. A game with sound does it some hundred times a second."""
        return self.amiga.lua("return heard")[0]

    def type(self, text: str) -> None:
        """Type on the keyboard."""
        self.amiga.lua(f"input.type({text!r})")

    def screenshot(self, name: str) -> None:
        """Save the picture as build/tests/<the run>/<name>.png."""
        self.amiga.screenshot(self.work / f"{name}.png")
