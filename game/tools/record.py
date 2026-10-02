"""Record video of the game, with its sound, from the emulator.

    tools/record.py out_dir clip [clip ...]      clips: title, stage-1, stage-3, ...

Each clip is recorded in an emulator of its own (amiga.py), at the Amiga's own speed
so that every frame is drawn, and comes out as out_dir/<clip>.mp4: 1920x1080 at the
Amiga's 49.92 frames a second, the game's 320x256 picture four times its size with
nothing smoothed, black beside it.

The picture is the emulator's own, a screenshot of every frame. The sound is not
the emulator's: this emulator cannot record what it plays. Instead every write to
Paula's registers is noted with the moment it was made, and the four channels are
played again from the notes afterwards (paula.py), mixed as an Amiga's, the left and
right pairs mostly apart.

`title` is the released game left alone: the title, the best scores, the attract
mode's game, and the title again. `stage-N` is a game from stage N (a build with
FIRST_STAGE), played by a stick this program moves (PLAYER below): it reads where
the enemies and the bombs are, keeps out of their way, and goes for what it can
shoot. The clip ends when the stage after it has begun, or after CLIP_FRAMES.

What is recorded has the arcade's graphics in it: it is for showing, not for the
repository. Needs ffmpeg, and numpy for the sound: uv run --with numpy tools/record.py ...
"""

import pickle
import shutil
import subprocess
import sys
from pathlib import Path

import paula
from amiga import Amiga, boot_directory
from game import GAME, PROGRAM, Game, header_values

CLIP_FRAMES = 6000  # two minutes: a clip is no longer
TITLE_FRAMES = 3600  # the title, the best scores, the attract mode's game and the title
AFTER_FRAMES = 150  # frames of the next stage that end a clip
FIGHTERS = 5  # in reserve when a clip's game starts: the option's six fighters
CROP = "640:512:76:36"  # the game's picture in the emulator's 756x576
RATE = "15625/313"  # frames a second: PAL
AUDIO_FIRST, AUDIO_LAST, DMACON = 0xDFF0A0, 0xDFF0DF, 0xDFF096
# The loudest a side gets in this game: the fighter's explosion at Paula's full volume with a
# tone at the driver's loudest (23) beside it, and what is mixed in of the other side's two
# tones. The sound is scaled so that this is full level.
LOUDEST = (127 * 64 + 120 * 23 + paula.OTHER_SIDE * 2 * 120 * 23) / (
    1 + paula.OTHER_SIDE
)

# The stick: every frame, from the game's state. Bombs and enemies near the fighter and
# above it are dangers, and it moves away from the nearest; with none, it goes under the
# nearest enemy in flight, or else under the formation's enemy nearest to it, and it
# presses the button every few frames while something is roughly above it.
PLAYER = """
local function player()
    local ship = mem.peek_u16({ShipX}) + {GUARD}          -- the fighter's left edge, in buffer pixels
    local line = {SHIP_Y} + {GUARD}
    local danger, danger_at, target, target_at = nil, 999, nil, 999
    for i = 0, {BOMBS} - 1 do
        local b = {Bombs} + i * {bm_SIZEOF}
        local x = mem.peek_u16(b + {bm_x})
        if x ~= 0 then
            local dx, dy = (x - {SPRITE_X}) - ship, line - (mem.peek_u16(b + {bm_y}) - {SPRITE_Y})
            if dy > -8 and dy < 70 and math.abs(dx) < 22 and math.abs(dx) + dy / 4 < danger_at then
                danger, danger_at = dx, math.abs(dx) + dy / 4
            end
        end
    end
    for i = 0, {FLIGHT_SLOTS} - 1 do
        local f = {Flights} + i * {fl_SIZEOF}
        if mem.peek_u8(f + {fl_flags}) & 1 ~= 0 then
            local dx, dy = mem.peek_u16(f + {fl_px}) - ship, line - mem.peek_u16(f + {fl_py})
            if dy > -16 and dy < 60 and math.abs(dx) < 26 and math.abs(dx) + dy / 3 < danger_at then
                danger, danger_at = dx, math.abs(dx) + dy / 3
            end
            if dy > 60 and math.abs(dx) < target_at then target, target_at = dx, math.abs(dx) end
        end
    end
    if not target then
        for row = 0, {FORM_ROWS} - 1 do
            local present = mem.peek_u16({FormPresent} + 2 * row)
            for column = 0, {HOME_COLUMNS} - 1 do
                if present & (1 << column) ~= 0 then
                    local dx = mem.peek_u8({HomeX} + 2 * column) - {SPRITE_X} - ship
                    if math.abs(dx) < target_at then target, target_at = dx, math.abs(dx) end
                end
            end
        end
    end
    local left, right = false, false
    if danger then
        -- away from it; at the edges, under it and out the other side
        if danger >= 0 then left = true else right = true end
        if ship < {GUARD} + 12 then left, right = false, true end
        if ship > {GUARD} + {PLAY_WIDTH} - 28 then left, right = true, false end
    elseif target then
        left, right = target < -1, target > 1
    end
    input.joy(1, 'left', left) input.joy(1, 'right', right)
    local aimed = target and math.abs(target) < 10
    input.joy(1, 'fire', aimed and emu.frame() % 6 < 2)
end
"""


def start_notes(amiga: Amiga, work: Path) -> None:
    """From now on every write to Paula's sound registers is noted, with its moment."""
    notes = (work / "paula.log").resolve()
    amiga.lua(
        f"notes = io.open({str(notes)!r}, 'w') "
        "local function note(address, value, size) "
        "notes:write(string.format('%d %d %d %d\\n', emu.cycles(), address, size, value)) end "
        f"mem.tap_write({AUDIO_FIRST}, {AUDIO_LAST}, note) "
        f"mem.tap_write({DMACON}, {DMACON + 1}, note)"
    )


def start_frames(amiga: Amiga, work: Path) -> None:
    """From now on every frame is saved as a picture, and its moment noted."""
    frames = (work / "frames").resolve()
    shutil.rmtree(frames, ignore_errors=True)
    frames.mkdir(parents=True)
    amiga.lua(
        "shown = 0 emu.on_frame(function() shown = shown + 1 "
        f"video.screenshot(string.format('{frames}/%06d.png', shown)) "
        "notes:write(string.format('%d frame %d 0\\n', emu.cycles(), shown)) "
        "if follow then follow() end end)"
    )


def finish(amiga: Amiga, work: Path, out: Path) -> None:
    """Stop, play the notes again as sound, and put picture and sound together."""
    amiga.lua("notes:close()")
    events, first, last = paula.read_notes(work / "paula.log")
    memory = {
        (at, length): bytes(
            amiga.lua(f"return mem.read_range({at}, {length})")[0], "latin-1"
        )
        for at, length in paula.waveforms(events)
    }
    amiga.stop()
    (work / "waves.pickle").write_bytes(
        pickle.dumps(memory)
    )  # to play the notes again later
    paula.render(events, memory, first, last, work / "sound.wav", LOUDEST)
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-framerate", RATE]
        + ["-i", str(work / "frames/%06d.png"), "-i", str(work / "sound.wav")]
        + [
            "-vf",
            f"crop={CROP},scale=1280:1024:flags=neighbor,pad=1920:1080:320:28:black",
        ]
        + ["-c:v", "libx264", "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p"]
        + ["-af", "lowpass=f=7000,aresample=48000", "-c:a", "aac", "-b:a", "256k"]
        + ["-shortest", "-movflags", "+faststart", str(out)],
        check=True,
    )


def record_title(work: Path, out: Path) -> None:
    """The released game left alone, from its first frame."""
    boot_directory(work / "hd", GAME / f"build/{PROGRAM}")
    amiga = Amiga(work, hard_drive=work / "hd", warp=False)
    start_notes(amiga, work)
    amiga.lua(
        f"dbg.load_symbols({str((GAME / f'build/{PROGRAM}.dbg').resolve())!r}, '{PROGRAM}', 1500)"
    )
    start_frames(amiga, work)
    for _ in range(TITLE_FRAMES // 500):
        amiga.wait(500)
    finish(amiga, work, out)


def record_stage(stage: int, work: Path, out: Path) -> None:
    """A game from a stage, played by PLAYER, until the next stage has begun."""
    subprocess.run(
        ["make", "-s", f"build/{PROGRAM}", f"DEFS=-DFIRST_STAGE={stage}"],
        cwd=GAME,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    boot_directory(work / "hd", GAME / f"build/{PROGRAM}")
    shutil.copy(GAME / f"build/{PROGRAM}.dbg", work)
    subprocess.run(["make", "-s"], cwd=GAME, check=True, stdout=subprocess.DEVNULL)
    game = Game.__new__(Game)
    game.v, game.work = header_values(), work
    game.amiga = Amiga(work, hard_drive=work / "hd", warp=False)
    game.symbols = (work / f"{PROGRAM}.dbg").resolve()
    start_notes(game.amiga, work)
    game.amiga.lua("emu.warp(true)")
    game.find()
    game.amiga.lua("emu.warp(false)")
    game.set("OptLives", FIGHTERS)
    names = {
        name: game.address(name)
        for name in ("ShipX", "Bombs", "Flights", "FormPresent", "HomeX")
    }
    game.amiga.lua(PLAYER.format(**{**game.v, **names}) + " follow = nil play = player")
    start_frames(game.amiga, work)
    game.press("fire")
    game.amiga.lua("follow = play")
    # the clip ends a little after the next stage has begun, or the game is over
    stage_at, state_at = game.address("Stage"), game.address("PlayerState")
    for _ in range(
        CLIP_FRAMES // 500
    ):  # a request at a time: each must be answered soon
        done = game.amiga.lua(
            "after = after or 0 for frame = 1, 500 do emu.wait_frames(1) "
            f"if mem.peek_u16({stage_at}) > {stage} "
            f"or mem.peek_u8({state_at}) == {game.v['PS_OVER']} then after = after + 1 end "
            f"if after > {AFTER_FRAMES} then return true end end return false"
        )[0]
        if done:
            break
    print(
        f"  stage {game.get('Stage', 2)}, score {game.get('Score', 4):06x},"
        f" {game.get('Lives')} fighters in reserve, state {game.get('PlayerState')}"
    )
    game.amiga.lua("follow = nil")
    finish(game.amiga, work, out)


def main() -> None:
    out_dir = Path(sys.argv[1]).expanduser()
    for clip in sys.argv[2:]:
        work = GAME / "build/record" / clip
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir(parents=True)
        if clip == "title":
            record_title(work, out_dir / "title.mp4")
        else:
            record_stage(
                int(clip.removeprefix("stage-")), work, out_dir / f"{clip}.mp4"
            )
        print(f"{clip}: {out_dir / (clip + '.mp4')}")


if __name__ == "__main__":
    main()
