"""Run the game's test builds in the emulator and check their reports.

    tools/run_tests.py                          everything (this is `make test`)
    tools/run_tests.py timing [frames] [-D...]  frame timing of a self-playing run,
                                                e.g. timing 4000 -DFIRST_STAGE=6
    tools/run_tests.py sound                    the sound driver against its model
    tools/run_tests.py flight                   the flight stepper against its model
    tools/run_tests.py stage [first:frames ...] the game against the models,
                                                e.g. stage 8:6000
    tools/run_tests.py play [scene ...]         the released game, played from outside
                                                (playtest.py), e.g. play pause
    tools/run_tests.py stress                   not part of everything: games played
                                                harder than the test builds play, at
                                                later stages, with four shots and two
                                                fighters; any frame that is late fails

A test build runs by itself, writes a report to the file "results" and exits. Every
run is built first, one after the other; then they all run at once, each in an
emulator of its own without a window and at full speed (see amiga.py), and each
report is given to its checker. All of it is in build/tests, a directory a run.

--stock runs them in the released FS-UAE instead: in windows and at the Amiga's own
speed. It is there to check the two emulators against each other. The released game
cannot be played from outside there, so those scenes are left out.
--jobs N runs N at once (default: as many as the host has processors).
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from amiga import KICKSTARTS, STOCK_A500, Amiga, boot_directory, pin_warning
from playtest import SCENES, STRESS, stress

GAME = Path(__file__).resolve().parent.parent
TOOLS = GAME / "tools"
TESTS = GAME / "build/tests"
ROM = os.environ.get("ROM", str(GAME.parent / "original/galaga.zip"))
BOOT_FRAMES = 1500  # more than Kickstart 1.3 needs to start the program
PAL_LINES = 313
# what `make test` times: the runs of CLAUDE.md's budget table
TIMING = (("", 4000), ("-DFIRST_STAGE=6", 4000), ("-DFIRST_STAGE=9", 4000))
STAGES = ("1:6000", "3:5500", "8:6000")


@dataclass
class Run:
    """One test build: how it is built, what it writes, and what checks that."""

    name: str
    defs: str
    frames: int  # frames the program runs for, at most
    size: int  # its report is at least this long
    check: list[str]  # the checker's command; the report's path is put for "@"
    no_late_frames: bool = False  # a timing report with a late frame fails
    scene: Callable[[Path], list[str]] | None = None  # or: the released game, played
    output: str = ""
    passed: bool = False
    seconds: float = 0.0


def tool(script: str, *arguments: str) -> str:
    """What one of the tools prints."""
    command = [sys.executable, str(TOOLS / script), *arguments]
    return subprocess.run(
        command, check=True, capture_output=True, text=True
    ).stdout.strip()


def timing_run(frames: int, defs: str, strict: bool) -> Run:
    name = "timing" + "".join(c if c.isalnum() else "-" for c in defs).lower()
    return Run(
        name,
        f"-DTEST_FRAMES={frames} {defs}",
        frames,
        12,
        ["report.py", "@"],
        no_late_frames=strict,
    )


def sound_run() -> Run:
    ticks = int(tool("sndtest.py", "ticks"))
    frames = ticks * 50 // 121 + 60
    return Run(
        "sound",
        f"-DTEST_FRAMES={frames} -DSOUND_TEST={ticks}",
        frames,
        ticks * 12,
        ["sndtest.py", "check", ROM, "@"],
    )


def flight_runs() -> list[Run]:
    size = 8 + 16 * int(tool("flighttest.py", "count", ROM))
    return [
        Run(
            f"flight-{'exact' if exact else 'pal'}",
            f"-DFLIGHT_TEST=1 -DEXACT_TIMING={exact}",
            12000,
            size,
            ["flighttest.py", "check", ROM, "@", str(6 - exact)],
        )
        for exact in (1, 0)
    ]


def stage_runs(specs: tuple[str, ...]) -> list[Run]:
    runs = []
    for spec in specs:
        first, frames = spec.split(":")
        for exact in (1, 0):
            defs = (
                f"-DSTAGE_TEST=1 -DCAPTURE=0 -DTEST_FRAMES={frames}"
                f" -DEXACT_TIMING={exact} -DFIRST_STAGE={first}"
            )
            check = ["stagetest.py", "check", ROM, "@", str(6 - exact), frames, first]
            name = f"stage-{first}-{'exact' if exact else 'pal'}"
            runs.append(Run(name, defs, int(frames), 1, check))
    return runs


def play_runs(names: tuple[str, ...]) -> list[Run]:
    return [Run(f"play-{name}", "", 0, 0, [], scene=SCENES[name]) for name in names]


def stress_runs(more: str) -> list[Run]:
    return [
        Run(f"stress-{name}", f"{defs} {more}", 0, 0, [], scene=stress(shots))
        for name, defs, shots in STRESS
    ]


def build(run: Run) -> None:
    """Build the run's program and put it where its emulator will boot from."""
    subprocess.run(
        ["make", "-s", "build/galaga", f"DEFS={run.defs}"],
        cwd=GAME,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    boot_directory(TESTS / run.name / "hd", GAME / "build/galaga")
    shutil.copy(GAME / "build/galaga.dbg", TESTS / run.name)


def emulate(run: Run) -> None:
    """Run the program until its report is written."""
    work = TESTS / run.name
    with Amiga(work, hard_drive=work / "hd") as amiga:
        amiga.wait_for_file(work / "hd/results", run.size, run.frames + BOOT_FRAMES)


def emulate_stock(run: Run) -> None:
    """The same in the released FS-UAE, which can only be watched from outside."""
    work = TESTS / run.name
    results = work / "hd/results"
    process = subprocess.Popen(
        [
            "fs-uae",
            "--amiga_model=A500",
            f"--kickstart_file={KICKSTARTS / STOCK_A500.kickstart}",
            "--slow_memory=0",
            f"--hard_drive_0={work / 'hd'}",
            "--floppy_drive_volume=0",
            "--automatic_input_grab=0",
        ],
        stdout=(work / "fs-uae.log").open("w"),
        stderr=subprocess.STDOUT,
    )
    try:
        deadline = time.monotonic() + (run.frames + BOOT_FRAMES) / 50 + 30
        last = -1
        while True:
            time.sleep(1)
            now = results.stat().st_size if results.exists() else 0
            if now >= run.size and now == last:
                return
            if time.monotonic() > deadline:
                raise TimeoutError(f"no report of {run.size} bytes ({now} bytes)")
            last = now
    finally:
        process.kill()
        process.wait()


def execute(run: Run, stock: bool) -> None:
    """Run one test and note what its checker says."""
    start = time.monotonic()
    results = TESTS / run.name / "hd/results"
    try:
        if run.scene:
            run.output = "\n".join(run.scene(TESTS / run.name))
            run.passed = True
            run.seconds = time.monotonic() - start
            return
        (emulate_stock if stock else emulate)(run)
        command = [str(results) if a == "@" else a for a in run.check]
        check = subprocess.run(
            [sys.executable, str(TOOLS / command[0]), *command[1:]],
            capture_output=True,
            text=True,
            check=False,
        )
        run.output = (check.stdout + check.stderr).rstrip()
        run.passed = check.returncode == 0
        if run.passed and run.no_late_frames:
            late = struct.unpack(">HIHHH", results.read_bytes()[:12])[4]
            run.passed = late == 0
    except Exception as error:  # noqa: BLE001  whatever went wrong is the result
        run.output = f"{type(error).__name__}: {error}"
    run.seconds = time.monotonic() - start


def main() -> None:
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument("--jobs", type=int, default=os.cpu_count())
    parser.add_argument("--stock", action="store_true")
    parser.add_argument("what", nargs="*")
    options, defs = parser.parse_known_args()
    what, arguments = (options.what or ["all"])[0], tuple(options.what[1:])
    if not options.stock and (warning := pin_warning()):
        print(warning)

    runs: list[Run] = []
    if what == "timing":
        runs.append(timing_run(int((arguments or ("200",))[0]), " ".join(defs), False))
    if what == "all":
        runs += [timing_run(frames, d, True) for d, frames in TIMING]
    if what in ("sound", "all"):
        runs.append(sound_run())
    if what in ("flight", "all"):
        runs += flight_runs()
    if what in ("stage", "all"):
        runs += stage_runs(arguments or STAGES)
    if what in ("play", "all") and not options.stock:
        runs += play_runs(arguments or tuple(SCENES))
    if what == "stress" and not options.stock:
        runs += stress_runs(" ".join(defs))
    if not runs:
        parser.error(f"no such test: {what}")

    start = time.monotonic()
    shutil.rmtree(TESTS, ignore_errors=True)
    try:
        for run in runs:
            build(run)
    finally:
        # leave the normal build in place, with its disk
        subprocess.run(["make", "-s"], cwd=GAME, check=True)
    with ThreadPoolExecutor(options.jobs) as pool:
        list(pool.map(lambda run: execute(run, options.stock), runs))

    for run in runs:
        verdict = "ok" if run.passed else "FAILED"
        print(f"{run.name}: {verdict} ({run.seconds:.0f} s)")
        print("".join(f"  {line}\n" for line in run.output.splitlines()), end="")
    failed = [run.name for run in runs if not run.passed]
    print(
        f"{len(runs) - len(failed)} of {len(runs)} passed"
        f" in {time.monotonic() - start:.0f} s"
        + (f"; failed: {', '.join(failed)}" if failed else "")
    )
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
