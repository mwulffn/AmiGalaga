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

- The formation itself: side-to-side drift while waves arrive, and the
  breathing afterwards. Homing enemies track it through two offset bytes
  the main CPU keeps updating.
- Which enemy dives when, bombs, the capture sequence, escorts and the
  transforming enemies. The scripts are extracted; the logic that starts
  them is in the main CPU and has not been ported.
- Choosing the sprite frame and flips from the heading. The arcade has
  six rotation frames per quadrant (15 degrees each) plus the upright
  pair, and flips by quadrant. That routine is not ported or validated
  here, because its result goes to sprite RAM, not to the slot.
- Frame rate. The scripts count arcade frames (60.6 Hz). On a 50 Hz PAL
  Amiga, one step per frame would make everything 17% slower; running six
  steps every five frames keeps the arcade's speed.

Reference used to find my way around the code: the commented disassembly
at https://github.com/hackbar/galaga. All addresses and behaviour here
were then checked against the ROM and MAME.
