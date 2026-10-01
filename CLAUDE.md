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
  are 14 lines (two blank lines each side, which overlap the next
  strip's when the rows are closed up); the boss strip is 18 with a
  blank line above and below. The blank lines wipe what a moving row
  leaves behind. A mask per row (`FormPresent`) says who is there.
- The formation moves as the arcade's does: it drifts sideways as a
  whole while the waves arrive (a pixel every 4 arcade frames, up to 32
  either way), then breathes (each column and row a pixel out or in
  every 4 frames by bit patterns from the ROM, 32 steps each way).
  `motion/formation.py` is the model: identical to the MAME trace's
  tables on all 33,016 frames of the 7 stages with a formation. The
  68000 version is `FormationTick`; `test_stage.sh` checks it every
  frame. The drift is added when strips are drawn, so all rows move
  together; breathing reaches a row when its strip is recomposed, so a
  row can be up to 5 frames (2 pixels) behind. When breathing starts
  the pulse sound starts, and follows its direction. The user has
  confirmed the breathing looks right (2026-10-01).
- A strip only wipes its own old image if it moves a line or two. A
  stage now ends with the formation empty, so the jump back to the rest
  position leaves nothing behind (the earlier demo, which changed stage
  with a full formation, did). If anything else ever resets a formation
  that still has enemies in it, the playfield has to be cleared then.
- **Flyers** (divers, bombs, explosions, score pop-ups): masked bobs,
  erased with a clear blit of the old position.
- **Text:** panel text is drawn by the CPU when it changes. Text inside
  the playfield (PLAYER 1, STAGE n, READY, GAME OVER, a challenging
  stage's results) is drawn as flyers of half height, two letters each,
  built from the font when a line is set and redrawn every frame while
  it shows (`game/src/text.s`): enemies fly through where the arcade
  puts its text. Three lines at most. Colours as the arcade: cyan, red
  for PERFECT, yellow for the special bonus.
- Rejected after measuring: clearing the whole buffer per frame, clearing
  with the CPU, and unmasked per-enemy copies (neighbours at 16 px pitch
  wipe each other).

### Hardware sprites
Sprites pair up and each pair shares three colours.

| Sprite | Use |
|---|---|
| 0, 1 | fighter on 0; its 32x32 explosion on both, left and right half (the pair's blue register is changed to the explosion's cyan in the copper list while it shows); second fighter on 1 when dual |
| 2, 3 | player bullets: both of the fighter's two on sprite 2, one below the other; sprite 3 for the dual fighter's second bullets, 15 pixels to the right |
| 4, 5 | captured fighter on 4: red, or white once rescued (the pair's three colour registers are set in the copper list for each use). When one of two fighters is lost, its explosion is on 4 and 5 while the other plays on; there is never a captured fighter while there are two |
| 6 | free, two usable colours; candidate for a second star layer |
| 7 | stars |

Both bullets on one sprite needs them 9 lines apart (the bullet's image
trimmed to its 8 lines, plus the line the hardware needs between two
uses of a sprite). A bullet climbs 6 lines an arcade frame and two
bullets keep their distance, so the only constraint is at launch: a
second press within a frame or two of the first waits until the first
shot is 9 lines up, instead of firing at once. **Accepted drift from the
arcade** (2026-10-01, the user tried the arcade and could not see the
overlap): at most a frame or two on a double tap faster than a hand can
do. A press while both shots are in flight is lost, as in the arcade.
Sprite reuse would also allow more than the arcade's two shots; that
option is kept for later.

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
- Scroll speed is the arcade's (`StarsTick`): a line per arcade frame on
  the first stages, a quarter more every fourth stage up to two lines at
  stage 16; the stars stand still while the fighter is not on screen
  (a game's opening, after a loss) and work back up to speed over about
  a second when it comes on. Checked on screenshots: no movement during
  the opening, then 60 lines a second. They run backwards while the
  tractor beam pulls the fighter up, as the arcade's do (in the code,
  not yet looked at on screen).

### Enemy movement
- Use the arcade's own flight scripts and wave tables, extracted from
  the user's ROM by `motion/extract.py`, and port the arcade's per-frame
  step routine. `motion/galaga_motion.py` is the reference port and is
  byte-identical to MAME (see `motion/README.md`).

- Waves are sent in as the arcade does it: a table of (path, enemy)
  pairs built from the stage's row, and a launcher that runs once per
  arcade frame. `motion/waves.py` is the model: all 396 launches of the
  trace's stages 1 to 9 happen at the frame the arcade made them.
- From stage 4 on a wave can have two or four extra enemies that fly
  through without joining the formation (objects $38 to $3E): random
  places among the wave's eight, half in each half of the wave; a
  butterfly, a bee, or in the second wave a boss; they never bomb on the
  way in, and count as alive while they fly. The arcade's random numbers
  come from the Z80's refresh register and cannot be reproduced, so the
  game has its own (`Random` in `stage.s`: a 16-bit multiply-and-add,
  with the beam position mixed in except in test builds, whose model
  makes the same numbers). For the check against the trace the places
  are read from the trace's own order of launches. The 68000 version is `game/src/stage.s`,
  checked by `game/tools/test_stage.sh` (see below).
- Dives are scheduled as the arcade does it (`game/src/dives.s`, model
  `motion/dives.py`): three timers (boss, butterfly, bee) counted every
  16 arcade frames, a limit on how many fly at once, restart values from
  ROM tables by stage, enemies left and time into the stage; a boss
  takes two escorts, or one, or goes alone, and they leave on successive
  frames. Predicting each frame of two MAME traces from the frame before
  (`trace_game.lua`, one with the bot firing and one without), the model
  matches the arcade's timers, queue and launches on 37,756 of 37,758
  frames and 298 of 299 launches; the misses are inputs that changed
  within the frame.
- A diver leaves its row's strip in the same frame: a row someone has
  left is rebuilt at once instead of waiting for its turn.
- The fighter and its shots are the arcade's (`game/src/player.s`, model
  `motion/shots.py`): a pixel and two pixels on alternate arcade frames
  while the stick is held; a shot hits every enemy within 5 pixels to
  the side and from 6 lines above to 5 below; a boss takes two hits;
  points by kind, double when flying, and 400, 800 or 1600 for a boss
  shot while diving by the escorts it set off with, shown as a pop-up.
  The hit box was tested against the firing trace: of 336 arcade hits
  the model finds 333, and 3 that the arcade did not have. An enemy
  blows up as in the arcade: three 16x16 frames and two 32x32 ones (four
  flyers each), stepped every fourth arcade frame.
- Bombs and losing the fighter are the arcade's (`game/src/bombs.s`,
  `player.s`, model `motion/bombs.py`): a flying enemy's timer and
  chances, a bomb aimed at the fighter when dropped, falling 2 and 3
  lines on alternate arcade frames, at most 8 at once; the fighter is
  lost to a bomb, or to an enemy once the stage's waves are in, within
  6 pixels to the side and 3 two-line steps up or down, and the enemy is
  destroyed too. Against the two traces: 533 of 535 bombs aimed as the
  arcade's, all 45,745 frames of falling the same, and all 66 losses
  explained by the box (59 with the fighter's position as traced, the
  rest within 2 pixels of it).
- Losing a fighter follows the arcade's sequence and timer: explosion
  (15 steps of 4 arcade frames, the noise sound), a pause of 4 counts of
  32 frames, then the next fighter comes on once the divers are home,
  can move for 3 counts, and is then in play. Attacks, new waves and
  bombs stop while it is out of play. With none left in reserve the game
  is over and a new one starts after 6 counts.
- Bombs are drawn as flyers of half height (their image is 8 lines).
- The flow between stages follows the arcade's sequence and its timer
  of 32-frame counts (`game/src/flow.s`): a game opens with PLAYER 1 and
  the start theme (8 counts), the first stage's splash, and the fighter
  coming on under PLAYER 1 and STAGE 1 (3 counts); a cleared stage is
  followed by 4 counts, then the next stage's splash (STAGE n for 3
  counts while its badges appear one every 8 frames with a click); a
  challenging stage has its own text and tune, a timer that spaces its
  waves, a bonus for all eight of a wave (1000 to 3000 by stage), and
  results (NUMBER OF HITS, BONUS at 100 a hit, or PERFECT and 10000);
  READY shows while a fighter is replaced, GAME OVER after the last.
  Stage badges are in the panel above SHIPS, not at the bottom right.
- Capture, rescue and the dual fighter are ported from the arcade's own
  tasks, with their counters (`game/src/capture.s`; no Python model yet,
  so `test_stage.sh` builds with `CAPTURE=0` and none of this is checked
  against MAME). Every other boss dive, while no boss is out capturing
  and the player has one fighter, is a capture attempt: the boss stops
  above where the fighter was, turns to point down and puts the beam
  out (10 rows, a row every few arcade frames by the stage's setting,
  held 64 frames, then back in). A fighter within 27 pixels of the
  beam's centre while it is held is taken: it spins, rises a line a
  frame, turns red near the top; FIGHTER CAPTURED and its tune; the boss
  carries it home, where it sits above the boss, and the player goes on
  with the next fighter (or the game is over). The boss shot before the
  fighter is all the way in lets it go.
- The beam is the arcade's 48x80 image in its three colour sets, copied
  into the playfield each frame it shows (one clear and one copy blit).
  The captured fighter is hardware sprite 4, not a flyer: its light blue
  is not in the 16-colour palette. It flies with its boss on later
  dives, turned as it flies; shot there it is worth 1000.
- Rescue: the boss shot while diving with its captured fighter frees it.
  It turns white, spins until nothing is flying (two counts at least),
  comes to the middle and down, the player's fighter moves over, and
  they are two, 15 pixels apart. No dives start meanwhile, and the
  fighter cannot be steered, fire or be hit while it makes room. If the
  player's fighter is lost while the rescued one is on its way, the
  rescued one takes its place.
- Two fighters fire two bullets a shot (the arcade's wider hit window),
  stop 16 pixels sooner at the right, and either can be hit: the one
  hit blows up, the other plays on, and bosses may capture again.
  `DUAL_START=1` builds a game that starts with two, for trying it out.
- Simplifications in capture, not the arcade's: the fighter cannot fire
  from inside the beam (the arcade's can, the way it points); a
  captured fighter that flies off alone after its boss is shot does not
  come back with a later stage's bosses, it is just gone.
- The user has not yet seen or played capture; it was checked on
  screenshots of self-playing builds only (2026-10-01).
- An enemy transforms as in the arcade (`game/src/transform.s`, model
  `motion/transform.py`): from stage 4 on, not on challenging stages,
  once the waves are in and fewer than 10 enemies are left, the first
  bee in its place (or else the first butterfly) is picked, flashes for
  64 arcade frames between its own colours and those of what it will
  become, and dives as a scorpion, a spy ship or a flagship by stage
  ((stage / 4) mod 3). Two more split off it on the way: the script's
  spawn command, which takes the first idle one of objects $38 to $3E
  and the last free flight. All three shot: 1000, 2000 or 3000. One
  that comes home is its old self again. One transformation a stage at
  most; none if the one picked is shot or dives while it flashes.
  Against the traces: the manager's timer, pick and launch are as the
  arcade's on all 13,693 frames it runs, with 5 picked and sent off;
  all 10 spawns take the arcade's slot and object and fly its first
  frame (the four bytes of a slot the arcade leaves as they were, among
  them the chances to bomb, are not compared: in the game a spawned
  enemy never bombs).
- The flashing is drawn in the row's strip: the picked enemy's bit in
  `FormAlt` makes the strip use its shape in the new colours
  (`flash.bin`: bee and butterfly, wings open and closed, in the three
  colour sets, 3 KB).
- The high score follows the score. An extra fighter comes at 20000, at
  70000 and every 70000 after (MAME's default switch setting).
- The wave timer was found because the launcher model started a
  challenging stage's waves too early; with it the model makes all 160
  trace launches at the arcade's frame with no unexplained waits.
- `test_stage.sh` runs a build that plays itself (side to side, a press
  every 16 frames) and compares every launch, landing, hit, kill, score,
  bomb, lost fighter and stage start with the models, in both builds:
  6,000 frames from stage 1 (through a stage change and a game over
  into the next game), 5,500 from stage 3 (a challenging stage, its
  results and bonus, and stage 4 with its fly-through enemies, some
  shot and some gone) and 6,000 from stage 6 (an enemy transforms in
  both builds). All identical. `STAGES="6:6000" tools/test_stage.sh`
  runs one of them.
- The stage index row is the arcade's difficulty switch; `RANK` 3 is
  what MAME's default (and the trace) uses.
- A flying enemy is turned the way it is heading by the arcade's rule
  (`FlightImage` in `game/src/game.s`): six frames 15 degrees apart per
  quadrant plus the upright one, mirrored by quadrant. The arcade's
  hardware flips sprites; the blitter cannot, so `make_gfx.py` writes
  every frame in all four flips (32 images a kind, 90 KB of chip RAM
  for the 11 kinds). The rule was read from the sub CPU's code, not
  checked against MAME: its result goes to sprite RAM, which the trace
  does not record. The user has looked at the entrance and the rotation
  on the emulated A500 and confirmed both look right (2026-10-01).
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

### Bombs (2026-10-01)

Self-playing runs of 2,500 frames. The stress run makes every flying
enemy drop a bomb whenever one is free and lets nothing hurt the fighter
(`BOMB_STRESS=1`), with the limit (`BOMBS`) varied:

| Run | Average | Worst frame |
|---|---|---|
| Normal play (limit 8, as the arcade) | 152 | 254 |
| Stress, limit 2 | 160 | 268 |
| Stress, limit 4 | 168 | 279 |
| Stress, limit 6 | 177 | 291 |
| Stress, limit 8 | 185 | 302 |

A bomb costs about 4 lines on average and 6 in the worst frame. With the
arcade's 8 the worst frame stays inside 313, by 11 lines. The limit is
`BOMBS` in `flight.i`; it stays at 8 until the user decides otherwise.
A cheaper bomb is possible: its image is 3 pixels wide, so 13 of 16 x
positions need a one-word blit, not two.

The user keeps the arcade's 8 and accepts the thin margin for now
(2026-10-01).

With the stage flow in, a self-playing run averages 158 lines. Its
worst frame, 292, is the one that sets a game's first stage up: the
stage's tables, five strips and a line of text are all built in that
frame, with nothing else on screen. Building a line of text is slow (a
byte at a time); if that frame ever matters, start there.

With capture in (2026-10-01), self-playing runs of 4,000 frames:

| Run | Average | Worst frame |
|---|---|---|
| Without capture (`CAPTURE=0`) | 156 | 295 |
| With capture, the beam cleared and then copied | 161 | 324 |
| With capture, the beam drawn in one pass | 161 | 306 |
| Two fighters from the start (`DUAL_START=1`) | 154 | 305 |

The beam's place is 80 lines of 4 words in 4 planes. Clearing it and
then copying the beam took a frame over 313 lines; one pass (the copy
for the rows that are out, a clear for the rest) does not. The margin
in the worst frame is 7 lines.

With the fly-through and transforming enemies in (2026-10-01), runs of
4,000 frames from three stages. The report now gives the worst frame's
number and lists the late ones (`tools/test.sh 4000 -DFIRST_STAGE=6`):

| From stage | Average | Worst frame | Frames over 313 |
|---|---|---|---|
| 1 | 161 | 310 | 0 |
| 6 | 164 | 333 | 8 |
| 9 | 158 | 337 | 3 |

**The game is over budget in its busiest frames from stage 6 on.** A
late frame is shown a frame late: a hitch of 1/50 s, no tearing (double
buffered; stars and sound run from interrupts and are not affected).
Two kinds of frame are late: the one that sets a stage up (frame 266
above: 332 to 337 lines with the wave table now built with its extras;
nothing moves on screen then), and play frames in a busy entrance (10
to 12 flying with bombs: 318 to 331). Not yet profiled. Candidates:
the cheaper bomb, the sound driver, splitting the stage set-up over two
frames.

A measuring error was fixed on the way: the frame count and the beam's
line were read one after the other, and a vertical blank between the
two made a frame that ended on its last line count as 625 lines.

A flyer costs about 6.4 lines to draw, the starfield 11-14. The arcade
never has more than 12 enemies flying at once; the rest of its
off-formation objects are bombs and explosions.

Moving a flight (`FlightStep`) costs about 1.8 raster lines, so 22 for
all 12. Measured in the test build over 440,000 steps with the display
and the silent sound driver running and the test's own bookkeeping
included, so the real figure is a little lower.

## Open

- **The game** (`game/`) so far plays from PLAYER 1 to GAME OVER and
  round again (the user has played it to stage 3 with a gamepad and
  says it plays really well, 2026-10-01): startup and shutdown, video, sound, starfield, flyers,
  formation strips, the panel (score, high score, stage badges, spare
  fighters), the flight stepper, the stage entrance, the formation's
  movement, dives, bombs, the player (joystick in port 2, shots, hits,
  explosions, score, lives, extra fighters), the flow between stages
  with its text, challenging stages with their results, and capture,
  rescue and the dual fighter. All to the
  style guide and linted.
- **Capture has no model.** A Python model of the beam, the rescue and
  the dual fighter, checked against a MAME trace with a capture in it,
  would let `test_stage.sh` run with capture on. The user knows of the
  gap and has put it off: fix it if something turns out to be amiss
  (2026-10-01). Also open there:
  firing from inside the beam, and the captured fighter that comes back
  in a later stage.
- **Game logic** not ported yet: the results after GAME OVER
  (shots, hits, ratio); title, attract mode and high score entry.
- **Over budget in busy frames from stage 6 on** (see Measured budget):
  about 2 frames in 1,000 are late, by up to 20 lines. An optimisation
  pass is due; the user has not yet said when.
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
  The user compared the game with the arcade in MAME (2026-10-01): the
  sounds and when they play are right; the arcade's effects sound more
  "direct" because it is mono, and the difference is accepted.
- **The fighter may have to move up about 4 lines.** It sits where the
  arcade's does, at display lines 241 to 256, so the last line is off
  the 256-line display and its 32x32 explosion (233 to 264) loses its
  bottom 8 lines. The user has seen the clipping; not decided yet
  (2026-10-01).
- **Not drawn yet:** the two-tile score
  pop-ups (2000 and 3000, for a challenging stage's wave from stage 19
  and for all three spy ships or flagships of a transformed enemy: the
  points are given, nothing shows).
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
| `cfg/` | MAME's own settings, written when the arcade is run from here; not ours, untracked |
| `original/` | the user's ROM set, ignored by git |

Python tooling follows the user's global rules: `uv`, ruff, type hints.
