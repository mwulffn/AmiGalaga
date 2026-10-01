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
  tight. The game's code follows the style guide: @docs/style.md
  (the experiments predate it and do not).
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
  The formation is where the arcade's is, read from the arcade's own
  two tables (`HomeLoc`, `HomeX` in the state), which the flights read
  too. At rest the rows' tops are at 36 (bosses), 52, 64, 76 and 88, 12
  pixels apart below the bosses, and the columns 16 apart from x = 32.
  The arcade moves the columns up to 32 pixels either way and the bottom
  row up to 32 down (measured over the MAME trace); strips are sized for
  that. Butterflies and bees are 10 rows tall upright, so their strips
  are 12 lines; the boss strip is 18 with a blank line above and below.
  A mask per row (`FormPresent`) says who is there.
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

- Waves are sent in as the arcade does it: a table of (path, enemy)
  pairs built from the stage's row, and a launcher that runs once per
  arcade frame. `motion/waves.py` is the model: all 160 launches of the
  trace's stages without fly-through enemies (1, 2, 3, 7) happen at the
  frame the arcade made them. The 68000 version is `game/src/stage.s`;
  `game/tools/test_stage.sh` compares its launches and landings over
  2,600 frames with the models, in both builds: identical.
- The stage index row is the arcade's difficulty switch; `RANK` 3 is
  what MAME's default (and the trace) uses.
- A flying enemy is turned the way it is heading by the arcade's rule
  (`FlightImage` in `game/src/game.s`): six frames 15 degrees apart per
  quadrant plus the upright one, mirrored by quadrant. The arcade's
  hardware flips sprites; the blitter cannot, so `make_gfx.py` writes
  every frame in all four flips (32 images a kind, 90 KB of chip RAM
  for the 11 kinds). The rule was read from the sub CPU's code and
  checked by eye, not against MAME: its result goes to sprite RAM, which
  the trace does not record.
- A landed enemy is drawn as a flyer at its place until its row's strip
  is next rebuilt (at most 5 frames), then it is part of the strip.

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
  drift) runs off the same fifths clock: the arcade's own logic gets one
  tick per arcade frame, so two in every fifth PAL frame (`Clock` in
  `game/src/game.s`). A flight launched by a tick waits out the part of
  the frame before it, so enemies in a line stay evenly spaced.
- Prototype and evidence: `motion/pal_scale.py`, 636 runs, always the
  same outcome as the arcade and within 9 pixels of it;
  `motion/render_compare.py` shows it side by side.
- The 68000 stepper is `game/src/flight.s` (`FlightLaunch`,
  `FlightStep`), a port of `motion/pal_scale.py`. `EXACT_TIMING=1`
  builds the 5-fifths version. `game/tools/test_flight.sh` flies 1,860
  cases (every entry path to every place in the formation, every dive
  and escort script, mirrored, with the fighter in different places and
  the hard-stage branches) in FS-UAE in both builds and compares each
  with the Python model: all identical, every frame.

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

### Wait loop or blit queue (experiment-7)

The same scene with sound and a stand-in for game logic (25,000 CPU
cycles a frame), drawn with the wait loop or with a queue that a
blitter-finished interrupt feeds. Average lines, worst frame in brackets:

| Machine, flyers | Wait, priority on | Queue, priority on | Wait, priority off | Queue, priority off |
|---|---|---|---|---|
| Stock A500, 10 | 238 (269) | 267 (301) | 268 (305) | 230 (254) |
| Stock A500, 20 | 301 (325) | 352 (379) | 340 (376) | 317 (625) |
| 1 MB fast RAM, 10 | 214 (241) | 185 (208) | 222 (250) | 179 (207) |
| 1 MB fast RAM, 20 | 279 (310) | 261 (292) | 291 (324) | 256 (288) |

- On a stock A500 the queue is no clear win: slightly better at 10
  flyers with priority off, worse at 20, and much worse with priority on
  (an interrupt per blit and nothing running in parallel).
- With fast RAM the queue wins by 20 to 40 lines, because the logic runs
  while the blitter works.
- That only happens if interrupt frames are off chip RAM. The system's
  supervisor stack is in chip RAM, where every access waits for the
  blitter; experiment-7 runs in supervisor mode on its own stack.
- With 25,000 cycles of logic, 20 full-size flyers do not hold 50 fps on
  a stock A500 in any of the four set-ups.

A flyer costs about 6.4 lines to draw, the starfield 11-14. The arcade
never has more than 12 enemies flying at once; the rest of its
off-formation objects are bombs and explosions.

Moving a flight (`FlightStep`) costs about 1.8 raster lines, so 22 for
all 12. Measured in the test build over 440,000 steps with the display
and the silent sound driver running and the test's own bookkeeping
included, so the real figure is a little lower.

## Open

- **The game** (`game/`) so far: startup and shutdown, video, sound,
  starfield, flyers, formation strips, score panel, fighter and bullet
  sprites, the flight stepper, and the stage entrance: each stage's five
  waves fly in and take their places. All to the style guide and linted.
  It cycles through stages 1 to 3 (`DEMO_STAGES`); `demo.s` stands in
  for the player. Stage 1's entrance with the start theme takes 131
  raster lines on average, 185 at worst (8 flying).
- **Not in the entrance yet:** the enemies that fly through without
  joining (stage 4 on; needs the arcade's random numbers), the wait
  before the first wave (READY, STAGE n), and holding waves back while
  the fighter is replaced.
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
- Loudness balance: in MAME's mix the explosion is 10.5 dB louder than
  the start theme. The first Amiga build had it 5 dB quieter (the user
  heard it as muted). Now the noise loop has its peaks flattened (rms 79
  of 127, same spectrum) and tones play at 1.5 x their arcade level
  (Paula volume 0-23), which puts the explosion 10.7 dB above the theme.
  That is as loud as the loop gets without changing its spectrum; any
  more has to come from turning the tones down. The user approved this
  balance by ear (2026-10-01). Paula's channels are hard-panned (0 and 3 left,
  1 and 2 right) while the arcade is mono; nothing is done about that.
- **Not drawn yet:** tractor beam, 32x32 explosions, dual fighter,
  READY/STAGE text.
- Second star layer on sprite 6: decide once logic shows the frame time
  left.

## Repository

| Path | Contents |
|---|---|
| `game/` | the game itself, written to the style guide: `make`, `make run`, `make test` (runs a test build in FS-UAE and prints its report) |
| `experiment-1` .. `experiment-7` | the experiments (1-5 rendering, 6 adds sound, 7 compares blit scheduling); each has `make run`, and `tools/measure.sh` for timing |
| `experiment-1/tools/extract_gfx.py` | sprites, font and palette from the ROM to Amiga bitplanes |
| `analysis/` | MAME Lua trace scripts and results (colours, sprite load, positions) |
| `motion/` | movement extraction, reference stepper, validation against MAME |
| `sound/` | sound extraction, driver and chip model, validation against MAME |
| `docs/style.md` | assembly style guide for the game's code |
| `asmlint/` | the header linter the style guide requires: a standalone Python tool (`uv run pytest` in its directory); the game's build runs it |
| `reference/` | local-only reading material, ignored by git |
| `original/` | the user's ROM set, ignored by git |

Python tooling follows the user's global rules: `uv`, ruff, type hints.
