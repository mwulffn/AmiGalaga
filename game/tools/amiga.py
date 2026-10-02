"""An emulated Amiga that a test drives from outside, through Lua.

This needs the FS-UAE with Lua scripting (github.com/mwulffn/fs-uae). FSUAE_LUA is
the path to its executable (default ~/Projects/fs-uae-lua/fs-uae/od-fs/fs-uae); the
client that talks to it is taken from the scripts directory beside it. The emulator
runs without a window and as fast as the host allows. With the cycle-exact
emulation left on, as it is here, that does not change what the Amiga does: a timing
report comes out the same as at normal speed.

Several can run at once: each has its own directory for temporary files, where
FS-UAE keeps the lock that stops a second copy, and its own port.
"""

import os
import shutil
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Self

FSUAE_LUA = Path(
    os.environ.get("FSUAE_LUA", Path.home() / "Projects/fs-uae-lua/fs-uae/od-fs/fs-uae")
)
KICKSTARTS = Path(
    os.environ.get("KICKSTARTS", Path.home() / "Documents/FS-UAE/Kickstarts")
)


@dataclass(frozen=True)
class Machine:
    """A model of Amiga: UAE's quickstart name, a Kickstart file, and options."""

    quickstart: str
    kickstart: str
    options: tuple[tuple[str, str], ...] = ()


# chipmem_size counts half megabytes, bogomem_size (slow RAM) quarter megabytes
STOCK_A500 = Machine(
    "A500,0", "kick34005.A500", (("chipmem_size", "1"), ("bogomem_size", "0"))
)

# Record the first exception that means a crash. Kickstart finds out what CPU it has
# by trying instructions a 68000 does not have, so the ROM's own are not counted.
CRASH_WATCH = """
crash = nil
dbg.exset("crash", function(vector, pc)
    if crash == nil and pc < 0xf80000 then
        crash = {vector = vector, pc = pc, frame = emu.frame(), registers = dbg.command("r")}
    end
end)
"""


class Crash(Exception):
    """The program on the Amiga took an exception that means it has crashed."""


class Amiga:
    """A running emulator. `lua` runs code in it and returns what the code returns."""

    def __init__(
        self,
        work: Path,
        machine: Machine = STOCK_A500,
        *,
        hard_drive: Path | None = None,
        floppy: Path | None = None,
        warp: bool = True,
        headless: bool = True,
    ) -> None:
        if not FSUAE_LUA.exists():
            raise FileNotFoundError(
                f"{FSUAE_LUA}: no FS-UAE with Lua there (set FSUAE_LUA)"
            )
        sys.path.insert(0, str(FSUAE_LUA.parent / "scripts"))
        from fsuae_lua import LuaClient

        work.mkdir(parents=True, exist_ok=True)
        tmp = work / "tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir()
        port = free_port()
        config = {
            "quickstart": machine.quickstart,  # first: it sets all the others
            "kickstart_rom_file": str(KICKSTARTS / machine.kickstart),
            **dict(machine.options),
            "sound_output": "none",
            "lua_port": str(port),
        }
        if hard_drive:
            config["filesystem2"] = f"rw,DH0:Test:{hard_drive.resolve()},0"
        if floppy:
            config["floppy0"] = str(floppy.resolve())
        (work / "amiga.uae").write_text(
            "".join(f"{key}={value}\n" for key, value in config.items())
        )
        # the SDL hints keep a window that is shown from taking the keyboard
        env = dict(
            os.environ,
            TMPDIR=str(tmp.resolve()),
            SDL_WINDOW_ACTIVATE_WHEN_SHOWN="0",
            SDL_WINDOW_ACTIVATE_WHEN_RAISED="0",
            SDL_MAC_BACKGROUND_APP="1",
        )
        self.work = work
        self.warp = warp
        self.process = subprocess.Popen(
            [
                str(FSUAE_LUA),
                *(["--headless"] if headless else []),
                str((work / "amiga.uae").resolve()),
            ],
            stdout=(work / "fs-uae.log").open("w"),
            stderr=subprocess.STDOUT,
            env=env,
        )
        deadline = time.monotonic() + 30
        while True:
            try:
                self.client = LuaClient(port, timeout=120)
                break
            except ConnectionRefusedError:
                if self.process.poll() is not None:
                    raise RuntimeError(
                        f"FS-UAE exited while starting: see {work / 'fs-uae.log'}"
                    ) from None
                if time.monotonic() > deadline:
                    self.process.kill()
                    raise
                time.sleep(0.05)
        self.lua(CRASH_WATCH)
        if warp:
            self.lua("emu.warp(true)")

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        self.stop()

    def lua(self, code: str) -> list[Any]:
        """Run Lua code in the emulator and return the values it returns."""
        return self.client.call(code)

    def frame(self) -> int:
        """The number of frames emulated so far."""
        return self.lua("return emu.frame()")[0]

    def wait(self, frames: int) -> None:
        """Let the Amiga run for a number of frames. Raises Crash if it crashed."""
        crash = self.lua(f"emu.wait_frames({frames}) return crash")
        if crash and crash[0]:
            c = crash[0]
            raise Crash(
                f"exception {c['vector']} at ${c['pc']:x} in frame {c['frame']}\n"
                f"{c['registers']}"
            )

    def wait_for_file(self, path: Path, size: int, frames: int) -> None:
        """Wait until the Amiga has written a file of at least `size` bytes.

        The file is done when it has not grown for 25 frames. Raises TimeoutError
        after `frames` frames without it, and Crash if the program crashed.
        """
        limit = self.frame() + frames
        last = -1
        while True:
            self.wait(25)
            now = path.stat().st_size if path.exists() else 0
            if now >= max(size, 1) and now == last:
                return
            if self.frame() > limit:
                raise TimeoutError(
                    f"no {path.name} of {size} bytes after {frames} frames"
                    f" ({now} bytes)"
                )
            last = now

    def screenshot(self, path: Path) -> None:
        """Save the picture the Amiga shows. Not every frame is drawn in warp mode,
        so it is turned off for a few frames."""
        self.lua(
            "emu.warp(false) emu.wait_frames(4) "
            f"video.screenshot({str(path.resolve())!r}) "
            f"emu.warp({'true' if self.warp else 'false'})"
        )

    def stop(self) -> None:
        """End the emulator."""
        try:
            self.lua("emu.quit()")
            self.process.wait(5)
        except Exception:  # noqa: BLE001  it is going away whatever happens
            self.process.kill()
            self.process.wait()


def free_port() -> int:
    """A TCP port nothing is listening on."""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def boot_directory(directory: Path, program: Path) -> Path:
    """Make a directory that, as a hard drive, starts `program` when booted."""
    shutil.rmtree(directory, ignore_errors=True)
    (directory / "S").mkdir(parents=True)
    shutil.copy(program, directory / program.name)
    (directory / "S/startup-sequence").write_text(f"{program.name}\n")
    return directory
