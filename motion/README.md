# Enemy movement

How the arcade moves its enemies, and tools to pull that data out of the
user's own ROM set (Namco rev. B `galaga.zip`). Nothing in this directory
contains ROM data; everything under `build/` is generated and must not be
committed or distributed.

    python3 extract.py ../original/galaga.zip build

| File | What it is |
|---|---|
| `galaga_motion.py` | ROM table addresses, script parser, and `step()`: a port of the arcade's per-frame flight routine |
| `extract.py` | writes `build/motion_data.s` (for the Amiga port), `build/paths.txt` (readable listing), `build/paths.png` (the 24 entry paths) |
| `trace_motion.lua` | MAME script: plays the game and dumps the motion queue every frame |
| `validate.py` | replays a trace through `step()` and compares every byte |
| `pal_scale.py` | prototype of the stepper at 1.2 arcade frames per PAL frame, compared with `step()` |
| `render_compare.py` | animates arcade timing and PAL timing side by side into `build/compare.gif` (needs pillow) |

## How the arcade does it

Up to 12 enemies fly at once. Each has a 20-byte slot (position in 9.7
fixed point, a 10-bit heading, speed, turn rate, a frame counter and a
script pointer) and is advanced once per frame by the sub CPU.

A script is a byte stream. A plain step is three bytes: two speeds (used
on alternating frames, so 2/3 means 2.5 pixels per frame), a signed turn
per frame, and a frame count. Bytes from `$ef` up are commands: jump,
conditional jumps (transient enemy, difficulty, last enemy standing),
"head for my formation slot", "dive to depth n", "pick this step's length
from eight values depending on where the fighter is", and a few one-offs
for the capture boss and escorts. `galaga_motion.NAMES` lists them all.

Movement per frame: the heading turns by the turn rate, then the position
moves `speed` along the dominant axis and `speed * fraction / 128` along
the other, where the fraction is how far the heading is into its 45 degree
octant. That is why Galaga's loops are rounded squares, not circles.

There are about 1.2 KB of scripts: 24 entry paths (6 for normal stages, 18
for challenging stages) and the dive scripts for bee, butterfly and boss.

Wave setup lives in the main CPU ROM: a stage row gives, for each of the 5
waves, the entry path of each half of the wave, whether the second half is
mirrored, and whether the two halves arrive together or in one line. The
path table adds a start position (top centre or lower sides). A stage row
is picked by rank and stage number through an index table.

`waves.py` is the model of that set-up and of the launcher that sends
the enemies in (one per frame at most; a wave starts once nothing is
flying; enemies in a line are 8 frames apart). Against the trace it
makes all 160 launches of stages 1, 2, 3 and 7 at the arcade's frame.
Enemies that only fly through (stage 4 on) are not modelled yet.

`formation.py` is the model of the formation's own movement: the drift
from side to side while waves arrive and the breathing afterwards. Its
tables are identical to the trace's on all 33,016 frames of the seven
stages that have a formation.

`dives.py` is the model of who leaves the formation to attack and when
(three timers, a limit on how many fly, a boss with its escorts). It is
checked against a second kind of trace, `trace_game.lua`, which dumps
the main CPU's working memory every frame (1,216 bytes; `game_trace.py`
reads it): each frame's timers, queue and launches are predicted from
the frame before. Over two traces (the bot firing, and not firing so the
formation stays whole) 37,756 of 37,758 frames and 298 of 299 launches
are as the arcade's; the misses are inputs that changed within a frame.

    GOUT=game.bin GFRAMES=40000 mame galaga -rompath ../original -video none \
        -sound none -nothrottle -skip_gameinfo -autoboot_script trace_game.lua
    python3 dives.py ../original/galaga.zip game.bin

`shots.py` is the model of the fighter's shots: how they move, what they
hit, and what it scores. Its hit box, tested on every shot, enemy and
frame of the firing trace, finds 333 of the arcade's 336 hits and 3 the
arcade did not have (positions that changed within the frame).

`bombs.py` is the model of the enemies' bombs (when one is dropped, how
it is aimed, how it falls) and of what destroys the fighter. Against the
two traces: 533 of 535 bombs aimed as the arcade's, all 45,745 frames of
falling the same, and all 66 lost fighters explained by its collision
box.

## Validation

`validate.py` against 38,600 frames of MAME (stages 1 to about 9, bot
playing): 84,627 slot-steps compared, 84,248 byte-identical. Every one of
the 379 differences is the main CPU writing to a slot in the same frame:
237 where the game freed the slot (enemy shot, wave reset) and 142 on the
capture boss while it holds still over the tractor beam.

To repeat it (the trace is about 17 MB):

    GOUT=motion.bin GFRAMES=40000 mame galaga -rompath ../original -video none \
        -sound none -nothrottle -skip_gameinfo -autoboot_script trace_motion.lua
    python3 validate.py ../original/galaga.zip motion.bin

## Not covered yet

- Bombs, the capture sequence, and the transforming enemies and their
  convoys. The scripts are extracted; the logic that starts them is in
  the main CPU and has not been ported.
- Choosing the sprite frame and flips from the heading is ported in the
  game (`game/src/game.s`) but not validated against MAME: its result
  goes to sprite RAM, not to the slot, and the trace does not record it.
- Frame rate: see the next section.

## Running at PAL speed

The scripts count arcade frames (60.6 Hz). `pal_scale.py` prototypes a
stepper that advances 1.2 arcade frames per 50 Hz frame, with the scripts
untouched, and compares it with the validated arcade stepper:

    python3 pal_scale.py ../original/galaga.zip [motion.bin]

How it counts time:

- A step's duration is held in fifths of an arcade frame. A PAL frame
  uses up 6; an "exact" build uses up 5 and must match the arcade.
- The heading is a 32-bit value (2^32 = a full turn). Turning is one add,
  and a long path does not drift: a 16-bit heading with a rounded 1.2
  factor ended up to 19 pixels off on the challenging-stage paths.
- Turn and distance for k fifths come from two small tables. When a step
  ends part-way through a PAL frame, each step contributes its share.
- When the script sets the heading (go home, capture aim), the old
  step's pending turn is dropped.
- At 1.2x the per-frame move is larger, so "reached home" accepts +-2
  units instead of +-1, and "reached dive depth" accepts having passed it.

Result over 636 runs (24 entry paths, both sides, every formation slot
for the normal-stage paths, plus 120 dives started from states the real
game produced): the exact build is identical to the arcade in all of
them. The PAL build always ends the same way (home, or off screen) and
stays within 9 pixels of the arcade's on-screen position at the same
moment; arrival differs by at most 3.2 arcade frames. Most of that
distance is along the path (a frame or two early or late), not a
different shape.

The 68000 version is `game/src/flight.s`. `game/tools/test_flight.sh`
flies 1,860 cases through it in FS-UAE, in the exact and the PAL build,
and compares every frame with `pal_scale.py`: all identical. It costs
about 1.8 raster lines per flight per frame.

Reference used to find my way around the code: the commented disassembly
at https://github.com/hackbar/galaga. All addresses and behaviour here
were then checked against the ROM and MAME.
