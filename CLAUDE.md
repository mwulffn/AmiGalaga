# Galaga for the Amiga 500

A port of the arcade game Galaga to the stock Amiga 500. The bar is
high-quality play-feel and sprites that match the arcade, not a
pixel-perfect copy. Where the Amiga can do better than the original
(the starfield), it should.

This file records what has been decided and why. Update it when a
decision is made or changed.

## Hard rules

- **Bring your own ROM.** The copyright status of Galaga is unclear, so
  nothing from the ROM is committed or distributed: not the ROM
  (`original/`), not anything generated from it (every `build/`
  directory), not the third-party disassembly (`reference/hackbar-galaga/`).
  Tools read the user's own `galaga.zip` (Namco rev. B) at build time.
  Small constants typed into tools (colour values, ROM addresses,
  checksums) are fine.
- **Target machine:** stock A500: 68000 at 7 MHz, OCS, 512K chip RAM,
  PAL, Kickstart 1.3. Do not rely on slow RAM or fast RAM.
- **Assembler:** vasm (`vasmm68k_mot`), Motorola syntax. Keep the code
  tight.
- **Measure, don't estimate.** Timing claims come from `tools/measure.sh`
  (FS-UAE as an A500). Things only visible on the display (hardware
  sprites, copper effects) are checked by capturing the FS-UAE window
  with `~/Projects/amiga-project/tools/fsuae-screenshot.sh`, or by the
  user looking.

## Decisions

### Display
- Low-res 320x256, 4 bitplanes, interleaved, double buffered, one fixed
  16-colour palette: black plus the 15 colours the arcade uses for
  enemies and text. Measured in MAME over stages 1-34 (`analysis/`).
- Blitter priority ("nasty") on. Game logic runs after the frame's
  drawing, not interleaved with it.

### Screen layout
- 224x256 playfield at the left, 16 px black gap, 80 px panel (10
  characters) at the right for score, high score and lives.
- The arcade's 224x288 screen loses its top two and bottom two text
  rows to the panel; all gameplay fits arcade lines 16-271.
- The buffer is 336x288: 16 hidden pixels at the left and 16 hidden
  rows above and below, so flyers need no clipping code. At the right
  edge the blit's first-word mask cuts off what would show in the gap.

### Rendering
- **Formation:** not 40 bobs. Each of its 5 rows is a pre-composed strip
  copied with one plain blit per frame; one strip is rebuilt per frame.
  No erase, no mask, and it repairs damage from flyer erases.
- **Flyers** (divers, bombs, explosions, score pop-ups): masked bobs,
  erased with a clear blit of the old position.
- **Text:** panel text is drawn by the CPU when it changes. Text inside
  the playfield (READY, STAGE n) will be bobs on the flyer path.
- Rejected after measuring: clearing the whole buffer per frame, clearing
  with the CPU, and unmasked per-enemy copies (neighbours at 16 px pitch
  wipe each other).

### Hardware sprites
Sprites pair up and each pair shares three colours.

| Sprite | Use |
|---|---|
| 0, 1 | fighter; second fighter when dual; the player explosion can reuse both |
| 2, 3 | player bullets, both reused vertically on sprite 2; sprite 3 for the dual shot |
| 4 | captured (red) fighter |
| 5 | free |
| 6 | free, two usable colours; candidate for a second star layer |
| 7 | stars |

### Starfield
- One sprite pixel, repositioned and recoloured per raster line by a
  copper table with no line numbers in it; scrolling is the table's
  start offset. Runs in the vertical blank interrupt at 50 Hz whatever
  the renderer does. Stars sit behind the bitplanes.
- One fixed field of about 200 stars, one per line at most, no star
  within two lines of another in the same or neighbouring column.
- Each star fades in three steps on its own period and phase, from a
  pre-computed 256-frame schedule. The user prefers this to the arcade's
  group blink.

### Enemy movement
- Use the arcade's own flight scripts and wave tables, extracted from
  the user's ROM by `motion/extract.py`, and port the arcade's per-frame
  step routine. `motion/galaga_motion.py` is the reference port and is
  byte-identical to MAME (see `motion/README.md`).

### Timing on PAL (approved 2026-10-01)
- The game runs at arcade speed on a 50 Hz display by advancing 1.2
  arcade frames per PAL frame. The arcade's scripts and tables are used
  untouched; nothing is hand-tuned.
- Time is counted in fifths of an arcade frame: a step lasting n arcade
  frames holds 5n, and each PAL frame uses up 6. A test build that uses
  up 5 must reproduce the arcade byte for byte, which keeps the check
  against MAME.
- Heading is 32 bits (2^32 = a full turn). Turn and distance per frame
  come from small tables; a step that ends part-way through a frame
  contributes only its share.
- "Reached home" accepts +-2 units and "reached dive depth" accepts
  having passed it, because the per-frame move is larger.
- Every other frame-counted timer (bombs, dive scheduling, formation
  drift) runs off the same fifths clock.
- Prototype and evidence: `motion/pal_scale.py`, 636 runs, always the
  same outcome as the arcade and within 9 pixels of it;
  `motion/render_compare.py` shows it side by side.

## Measured budget

A PAL frame is 313 raster lines. Drawing time, blitter priority on:

| Scene | Lines | Worst frame |
|---|---|---|
| 50 brute-force bobs (experiment-1) | 301 | 302 |
| Formation only | 81 | 99 |
| Formation + 10 flyers + panel + stars | 157 | 178 |
| Formation + 20 flyers + panel + stars | 225 | 246 |

A flyer costs about 6.4 lines, the starfield 11-14. The arcade never has
more than 12 enemies flying at once; the rest of its off-formation
objects are bombs and explosions.

## Open

- **The 68000 flight stepper** (both the PAL and the exact build) is not
  written; its cost, estimated at about 8 raster lines for 12 flyers, is
  not measured.
- **Game logic** is not ported or measured: formation drift and
  breathing, dive scheduling, bombs, capture, scoring.
- **Sound** has not been looked at.
- **Not drawn yet:** tractor beam, 32x32 explosions, dual fighter,
  READY/STAGE text.
- Second star layer on sprite 6: decide once logic shows the frame time
  left.

## Repository

| Path | Contents |
|---|---|
| `experiment-1` .. `experiment-5` | the rendering experiments; each has `make run`, and `tools/measure.sh` for timing |
| `experiment-1/tools/extract_gfx.py` | sprites, font and palette from the ROM to Amiga bitplanes |
| `analysis/` | MAME Lua trace scripts and results (colours, sprite load, positions) |
| `motion/` | movement extraction, reference stepper, validation against MAME |
| `reference/` | local-only reading material, ignored by git |
| `original/` | the user's ROM set, ignored by git |

Python tooling follows the user's global rules: `uv`, ruff, type hints.
