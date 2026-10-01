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

### Sound
- The arcade's three tone voices are synthesised on Paula as wavetable
  voices from the arcade's own 32-sample waveforms; the fourth Paula
  channel is for noise. Only the fighter's own explosion uses the
  arcade's noise chip (enemy hits are tones); it will be noise of our
  own, matched to MAME's output: about 2.7 s, 100-800 Hz, full level
  for 0.2 s then halving every half second. Approved by ear
  (2026-10-01): a half-second noise loop at 8 kHz (4000 bytes), with the
  decay set through Paula's volume once per frame. 4 kHz sounded tinny;
  12 kHz was not distinguishable from 8 on desktop speakers. Sampling everything was rejected: about 36 s of
  one-shot sounds will not fit 512K at a decent rate, and recordings
  could not ship.
- The sound driver runs at the arcade's 121 Hz from a CIA timer, not
  from the display, so tempo needs no scaling.
- `sound/` extracts every sound from the user's ROM. Its driver model is
  identical to MAME on all 78,575 ticks of a gameplay trace. Highest
  pitch is 2143 Hz, so waveform copies down to 8 samples are enough.
- The Amiga driver (`experiment-6/src/sound.s`) is a port of the driver
  logic, not stream playback. It is checked against the arcade model by
  a scripted run in FS-UAE (`tools/measure.sh sndtest`): 6,774 ticks,
  all identical. The game requests sound n by writing byte 2*n of
  `snd_state`. Size: 1.5 KB code, 3.2 KB tables, 0.5 KB state, 4.4 KB
  of samples in chip RAM.

## Measured budget

A PAL frame is 313 raster lines. Drawing time, blitter priority on:

| Scene | Lines | Worst frame |
|---|---|---|
| 50 brute-force bobs (experiment-1) | 301 | 302 |
| Formation only | 81 | 99 |
| Formation + 10 flyers + panel + stars | 157 | 178 |
| Formation + 20 flyers + panel + stars | 225 | 246 |

| Formation + 10 flyers + panel + stars + sound | 174 | 213 |
| Formation + 20 flyers + panel + stars + sound | 247 | 294 |

Sound costs CPU time, not blitter time: a driver tick is about 890 CPU
cycles when silent, 2,400 with the start theme, 3,500 in a busy stretch
(pulse, shots, hits, dives), at 121 ticks a second. That is 5, 13 and 19
raster lines per frame.

A flyer costs about 6.4 lines, the starfield 11-14. The arcade never has
more than 12 enemies flying at once; the rest of its off-formation
objects are bombs and explosions.

## Open

- **The 68000 flight stepper** (both the PAL and the exact build) is not
  written; its cost, estimated at about 8 raster lines for 12 flyers, is
  not measured.
- **Game logic** is not ported or measured: formation drift and
  breathing, dive scheduling, bombs, capture, scoring.
- **Sound cost: deferred, by decision.** The driver works and the user
  has confirmed it sounds right on the emulated A500 (2026-10-01). At up
  to 19 lines a frame it is the largest CPU item measured, and it lifts
  the worst frame with 20 flyers to 294 of 313 lines. Make it fast later
  ("first work, then fast"). Ideas, none tried yet:
  - test two sounds per instruction by laying the request bytes out in
    handling order;
  - a lighter path for the one-voice sounds (shots, hits, dive), which
    are most of a busy stretch;
  - play some sounds from pre-computed per-tick streams;
  - run two driver steps per interrupt at 60 Hz and write Paula once.
  Any change must still pass `experiment-6/tools/measure.sh sndtest`.
- The explosion's loudness against the tones is a guess; nobody has
  compared it with the arcade's mix.
- **Not drawn yet:** tractor beam, 32x32 explosions, dual fighter,
  READY/STAGE text.
- Second star layer on sprite 6: decide once logic shows the frame time
  left.

## Repository

| Path | Contents |
|---|---|
| `experiment-1` .. `experiment-6` | the experiments (1-5 rendering, 6 adds sound); each has `make run`, and `tools/measure.sh` for timing |
| `experiment-1/tools/extract_gfx.py` | sprites, font and palette from the ROM to Amiga bitplanes |
| `analysis/` | MAME Lua trace scripts and results (colours, sprite load, positions) |
| `motion/` | movement extraction, reference stepper, validation against MAME |
| `sound/` | sound extraction, driver and chip model, validation against MAME |
| `reference/` | local-only reading material, ignored by git |
| `original/` | the user's ROM set, ignored by git |

Python tooling follows the user's global rules: `uv`, ruff, type hints.
