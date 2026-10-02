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
- **PAL only** (the user's decision, 2026-10-02). On an NTSC A500 the
  game runs a fifth too fast (72 arcade frames a second) and the bottom
  of the playfield, with the fighter, is off the screen; nothing is
  done about it, and the release says so.
- **Assembler:** vasm (`vasmm68k_mot`), Motorola syntax. Keep the code
  tight. The game's code follows the style guide: @docs/style.md
  (the experiments predate it and do not).
- **Measure, don't estimate.** Timing claims come from the emulator as a
  stock A500 with its cycle-exact emulation on: `game/tools/run_tests.py`
  (see Tests), or `tools/measure.sh` in the experiments. Things only
  visible on the display (hardware sprites, copper effects) are checked
  on screenshots the tests take through the emulator's Lua
  (`Amiga.screenshot` in `game/tools/amiga.py`), or by the user looking.

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
  No erase, no mask, and it repairs damage from flyer erases. Only the
  part of a strip with enemies in it is copied: from a blank word
  before the first to two blank words after the last, joined with what
  was copied at the two drawings before (each screen is drawn every
  other frame), so what an enemy leaves behind when it goes is wiped
  from both screens and an empty row then costs nothing.
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
  68000 version is `FormationTick`; the stage test checks it every
  frame. The drift is added when strips are drawn, so all rows move
  together; breathing reaches a row when its strip is recomposed, so a
  row can be up to 5 frames (2 pixels) behind. When breathing starts
  the pulse sound starts, and follows its direction. The user has
  confirmed the breathing looks right (2026-10-01).
- A strip only wipes its own old image if it moves a line or two. A
  cleared stage ends with the formation empty, so the jump back to the
  rest position leaves nothing behind. When a formation with enemies in
  it is taken away (a game is over: `StageIdle`), it is emptied where it
  stands, not put back at rest: its strips, rebuilt empty, are drawn
  once more where the enemies were and wipe them, at no extra cost. The
  next stage's start puts the formation at rest. (Wiping the whole
  playfield with the blitter was tried first: about 270 lines a screen.)
- **Flyers** (divers, bombs, explosions, score pop-ups): masked bobs,
  erased with a clear blit of the old position.
- **Text:** panel text is drawn by the CPU when it changes. Text inside
  the playfield (PLAYER 1, STAGE n, READY, GAME OVER, a challenging
  stage's results) is drawn as flyers of half height, two letters each,
  built from the font when a line is set and redrawn every frame while
  it shows (`game/src/text.s`): enemies fly through where the arcade
  puts its text. Six lines at most, and 56 flyers of text and bombs on
  screen at once. Colours as the arcade: cyan, red
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
| 6 | the far stars (experimental, see Starfield): a list of one-line images, in the pair's second and third colours |
| 7 | the near stars: armed by hand and moved by the copper, in the pair's first colour, which the star table changes on every line |

Every bullet on one sprite needs them 9 lines apart (the bullet's image
trimmed to its 8 lines, plus the line the hardware needs between two
uses of a sprite). A bullet climbs 6 lines an arcade frame and two
bullets keep their distance, so the only constraint is at launch: a
second press within a frame or two of the first waits until the first
shot is 9 lines up, instead of firing at once. **Accepted drift from the
arcade** (2026-10-01, the user tried the arcade and could not see the
overlap): at most a frame or two on a double tap faster than a hand can
do. A press while both shots are in flight is lost, as in the arcade.
Sprite reuse also allows more than the arcade's two shots: the SHOTS
option, up to four.

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

- **The far stars: experimental** (2026-10-02, the user's wish: "a
  slower dimmer field on the last available sprite"; on the branch
  `second-stars`). A second layer of 24 stars on sprite 6, behind the
  near ones, scrolling half as fast (`FAR_SLOWER` in `stars.s`; a
  quarter was tried first and was too slow), downwards only: they stand
  still while the near ones run backwards. Each has one of the near
  stars' hues at half their brightness, and twinkles.
  - Where they are: they cannot be placed by the near stars' copper
    table, which scrolls as one, so they are an ordinary sprite: a list
    of one-line images in chip RAM, one for each star, 4 lines apart at
    least (a sprite needs a line between two uses). When they move a
    line the vertical blank interrupt writes every star's place into
    the list again (`FarPlace`), starting with the highest on the
    screen: the star that leaves at the bottom comes in at the top and
    is the first from then on.
  - How they look: the sprite pair has three colours; the near stars
    use the first and the far stars the second, and every entry of the
    star table now sets both for its line (an entry is 16 bytes, the
    table 8 KB). A far star's colour must be in the entry that runs on
    the line the star is on, which is another entry every frame, so
    every frame each star's colour is written to where it is needed
    (`FarColour`). They twinkle four at a time in turn (`FarTwinkle`):
    a star moves on in a brightness wave of 32 steps that all share,
    from its own place in it and at its own rate, 1 to 3 steps a turn.
  - `tools/make_stars.py` makes them (`stars2.bin`, `looks2.bin`).
    Checked on screenshots: every lit star is found in the colour its
    state has, near where its place says.
  - What it costs: all of it is in the vertical blank interrupt, which
    the stress runs' measure (from the frame's first work to the flip)
    mostly does not see; the timing runs count from the frame's start
    and do. Their average and worst lines from stages 1, 6 and 9:
    without far stars 127 and 246 from stage 1; with them 138 and 257,
    139 and 304, 148 and 286. So about 10 lines a frame, and 9 lines to
    spare in the worst frame of those runs. Late frames in the five
    stress runs: 1, 0, 1, 0 and 29 (without: 0, 0, 0, 0 and 11). The
    first version (two fixed dim colours, no twinkle, nothing written
    every frame) cost under 2 lines a frame, with late frames 1, 0, 0,
    0 and 16.
  - The user has not seen this version yet.

### The fighter is 10 lines higher than the arcade's (decided 2026-10-02)
- The arcade's fighter is at sprite y 297: display lines 241 to 256, its
  last line off this 256-line display, and its 32x32 explosion (233 to
  264) cut off at the bottom. Here it is 10 lines higher (`SHIP_RAISED`
  in `layout.i`): lines 231 to 246, the explosion 223 to 254. The user
  looked at it 9 higher and approved; 10 because the number must be
  even (the build fails on an odd one): the arcade compares heights
  halved, and an odd shift would move what hits the fighter by a line
  against the fighter itself.
- Everything that goes by the fighter's line goes with it, through the
  one constant: where its shots start, what touches it (enemies and
  bombs), what the bombs are aimed at, the line it is pulled up from
  and let back down to, and the line a rescued fighter comes down to.
  What does not move: the enemies' paths, which are the arcade's, so a
  diver or a bomb reaches the fighter 10 lines sooner; the height a boss
  hovers at and the beam under it, so 10 lines more of the beam overlap
  the fighter and a taken fighter has 10 lines less to rise; where a
  shot is gone at the top. A shot is now at heights 4 lines off the
  arcade's on each frame (it climbs 6 a frame from another start).
- A rescued fighter that is freed below the fighter's line goes round
  by the top, as the arcade's does (its y has 9 bits); the band where
  that happens is 10 lines taller. Not seen in play.
- The models take the same height (`SHIP_RAISED` in `stagetest.py`,
  the aim's `fighter_half_y` in `motion/bombs.py`, whose default is the
  arcade's, so the checks against MAME are as they were). The stage
  test is identical in all six runs with it. The user has played it
  with the fighter raised and confirmed capture, rescue and how it
  plays (2026-10-02). No test plays a capture or a rescue: a scene that
  does it from outside was attempted and given up (a fighter that
  stands still for the beam is bombed first, at the arcade's height
  too).

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
  checked by the stage test (`game/tools/run_tests.py stage`, see below).
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
  blows up as in the arcade: three 16x16 frames and two 32x32 ones,
  stepped every fourth arcade frame. A 32x32 frame is one blitter
  object with its own list to erase from (`BigDraw` in `flyers.s`),
  which is not clipped: one that would hang over an edge of the buffer
  or show in the gap is drawn as four flyers instead, as they all were
  before. A score that
  follows (400 to 1600 for a boss, 1000 to 3000 for a challenging
  stage's wave or a transformed enemy's three) shows for 19 steps where
  the enemy was; 2000 and 3000 are two images side by side, as in the
  arcade.
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
  so the stage test builds with `CAPTURE=0` and none of this is checked
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
- The user has played and confirmed capture, rescue, the dual fighter
  and the transformation into scorpions, and the results screen
  (2026-10-01).
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
- After GAME OVER and its pause the results show for 14 counts, as in
  the arcade: -RESULTS-, SHOTS FIRED, NUMBER OF HITS, HIT-MISS RATIO,
  in its places and colours (red, yellow, yellow, white), built a line a
  frame. A shot is a press that fired (one for two fighters' pair of
  bullets); a hit is each enemy a shot hits, a boss's first hit
  included. The ratio is hits per hundred shots to a tenth, worked out
  exactly; the arcade's own division is approximate, so its last digit
  can differ.
- The high score follows the score. An extra fighter comes at 20000, at
  70000 and every 70000 after (MAME's default switch setting).
- The wave timer was found because the launcher model started a
  challenging stage's waves too early; with it the model makes all 160
  trace launches at the arcade's frame with no unexplained waits.
- The stage test runs a build that plays itself (side to side, a press
  every 16 frames) and compares every launch, landing, hit, kill, score,
  bomb, lost fighter and stage start with the models, in both builds:
  6,000 frames from stage 1 (through a stage change, a game over and
  its results into the next game), 5,500 from stage 3 (a challenging
  stage, its results and bonus, and stage 4 with its fly-through
  enemies, some shot and some gone) and 6,000 from stage 8 (an enemy
  transforms in both builds). All identical.
  `tools/run_tests.py stage 8:6000` runs one of them. Which run
  contains a transformation depends on how the self-playing game goes:
  check with the model when the game's timing changes (the run from
  stage 6 lost its transformation when the results screen came in).
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

### Title, options, best scores (decided by the user, 2026-10-01)
- The arcade's coins, credits and second player are dropped. So is its
  table of what each enemy scores.
- **Released as AmiGalaga, source under the MIT licence** (the user's
  decision, 2026-10-02): the program, its symbol file and the disk
  image are `build/AmiGalaga`, `AmiGalaga.dbg` and `AmiGalaga.adf`
  (`NAME` in the Makefile, `PROGRAM` in `tools/game.py`), and the
  disk's name is AmiGalaga. The licence is for what is in the
  repository; the README says that it gives no right to Galaga, and
  that what is built must not be handed on.
- The game is called **AmiGalaga**. Namco's name and copyright line are
  not shown.
- What shows when no game is on (`game/src/title.s`): the title with
  START GAME, OPTIONS and QUIT (stick up and down, button to take one);
  left alone for 8 seconds it gives way to the best scores, and they to
  the title. A game that ends comes back to the title after its results.
- QUIT ends the program and gives the machine back to the system, so
  the game is a good citizen when run from a hard disk. (The left mouse
  button still does the same at any time.) The sound driver's CIA-B
  timer and interrupt mask are put back as the system had them, asked
  of `ciab.resource` beforehand.
- Best scores: five, each with three initials (A to Z, full stop,
  space). A game that ends with one of them goes to the list, its score
  in as AAA in yellow: stick left and right changes the blinking
  letter (held, it runs on), the button takes it; 20 seconds without a
  touch takes them as they are. The arcade's tunes play: its own for
  the best of all, a loop for the others.
- **Saving, kept defensive** (`startup.s`, the only file that calls the
  system): the scores are read from `AmiGalaga.scores` in the directory
  the game was started from, before the machine is taken, and written
  back after it has been given back, on QUIT, if they have changed. The
  game never touches the disk while it runs, so scores are lost if the
  machine is switched off without QUIT (the user's choice, 2026-10-01).
  Nothing about the file can stop the game: the system's requesters
  are off for the process (`pr_WindowPtr` = -1), a file of the wrong
  size, mark or checksum, or with anything in it that is not a score or
  a letter, is ignored, and a disk that cannot be written is left.
  Checked by the play scenes `initials` and `floppy` (see Tests), on
  the released build: from a hard-drive directory and from a floppy
  image the file is written and read back on the next start; a damaged
  file gives the arcade's scores; a floppy image that cannot be written
  ends at the AmigaDOS prompt with no requester, the image unchanged,
  and the game starts again from there.
- Options: FIGHTERS 3 or 6 (the user's choice; the arcade's switch has
  2 to 5), SHOTS 2 to 4 (how many can be in flight at once; 2 is the
  arcade's) and DIFFICULTY, which is the arcade's own switch: easy (its
  default, and what the traces and tests use), medium, hard, hardest.
  It picks the rank's row of the stage index and of the stage settings
  at run time (`Rank` in the state; `RANK` in `config.i` is only the
  value it starts with). Settings last until power-off.
- The arcade's other switches: bonus fighters (eight schedules; the
  game has the default, 20000, 70000 and every 70000), demo sounds,
  freeze, rack test (skip a stage), cabinet, coinage. None offered.
- Attract mode: after the best scores a game plays by itself with one
  fighter, silently, under PUSH FIRE TO PLAY, until the fighter is lost
  (45 seconds at most) or the button is pressed; then the title. The
  player is the test builds' (side to side, a press every 16 frames),
  and the score counts for nothing. It is the game itself, not the
  arcade's scripted demonstration, which is not ported.
- P pauses a game and lets it go on (`keys.s`: the keyboard is asked
  directly, once a frame, and answered with the beam for a clock;
  `main.s`): nothing moves, the sound is held, PAUSED shows in the
  panel. Not in the attract mode or the menus. Checked by the play
  scene `pause`, which presses the emulated keyboard's keys: P holds the
  game, the stars and the sound and lets them go, every press counts,
  and no other key does anything.
- More shots: all of a fighter's shots are on one sprite, top one
  first, each 9 lines or more under the one above; firing waits for
  that room as it did for two. With SHOTS at 2 the game is as before
  (the stage test is unchanged and identical). Tried on screenshots at
  4 with two fighters and fast automatic fire.
- **The logo** (the user's choice of five drawn, 2026-10-02): AMIGALAGA
  in block letters, yellow over gold over rust with a white top edge and
  a blue shadow, 192 x 30. The letters are the game's own, drawn on a
  grid in `tools/make_logo.py` (five of them: A, M, I, G, L); nothing of
  the arcade is in them, and nothing of its logo. It is a picture in
  the playfield, not text: copied into a screen once when the title
  comes and cleared once when it goes (`logo.s`). Each screen remembers
  whether it has it (`scr_logo`), and what is on is asked of `Mode`, so
  the title's code knows nothing of it. Seen on screenshots: on the
  title, gone on the options, back, gone when a game starts.
- **The icon and starting from Workbench** (2026-10-02): the disk has
  `AmiGalaga.info`, a fighter of the game's own drawing (the user's
  choice of three) in Workbench's four pens, made by
  `tools/make_icon.py` in the old icon format every Kickstart reads.
  The pens are other colours on 1.3 than on 2.0 and later, so it is a
  body in pen 1 with an edge in pen 2. `startup.s` takes Workbench's
  message first, makes the program's directory (which comes with the
  message) the current one so that the best scores are beside the
  program, puts the old one back at the end, and answers the message
  last, under Forbid. Tried on Workbench 3.1 (an A1200, a copy of the
  user's hard disk image, the pointer worked from outside): the disk's
  window shows the icon; a double click starts the game; the left mouse
  button ends it and Workbench is as it was (the same graphics memory
  free); a second start works; a best score entered is written to the
  floppy and read back at the next start from the icon. The same on
  Workbench 1.3 on a stock A500 with 512K (Workbench from its disk in
  DF0, the game's in DF1: 341,000 bytes are free, and the game fits):
  the icon shows, the game starts from it twice with a quit between,
  and the scores go to the game's disk, not Workbench's. The user has
  seen the logo and the icon on Workbench 3.1 and approved both. The
  disk has no icon of its own: Workbench shows its usual one.
  Commodore's Workbench disks are not ours: `*.adf` in the repository's
  root is ignored by git.
- While the title, the options or the best scores show, the stars
  drift slowly: a quarter of a line per arcade frame, 15 lines a second
  (`TITLE_SPEED` in `stars.s`). Asked for and confirmed on screen by
  the user (2026-10-01).
- A test build (`TEST_FRAMES` and the like) skips all of this and goes
  straight into a game, so the tests are as they were.

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
  builds the 5-fifths version. `game/tools/run_tests.py flight` flies 1,860
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

## Tests

The tests need the FS-UAE with Lua scripting (github.com/mwulffn/fs-uae;
`FSUAE_LUA` is its executable, by default
`~/Projects/fs-uae-lua/fs-uae/od-fs/fs-uae`). It runs without a window,
at full speed (about nine times the Amiga's) with the cycle-exact
emulation on, and several at once. Decided 2026-10-02.

- **The emulator is pinned** to the fork's commit `9ecc044` (UAE core
  from WinUAE 6.0.3): `FSUAE_COMMIT` in `game/tools/amiga.py`, and the
  tests warn if the checkout the emulator is in is at another. That is
  the commit the comparison with the released FS-UAE below was made
  with. Before moving it on, run `run_tests.py --stock` and the suite
  on the new one and compare the reports in `build/tests` again; trust
  no new timing figure until that is done.

- `game/tools/amiga.py` starts an emulator and talks to it: Lua code in,
  values out. It watches for exceptions that mean a crash (not the
  ROM's own: Kickstart tries instructions to find out what CPU it has).
  A configuration file must be given by its full path: a relative one
  is silently not read.
- `game/tools/run_tests.py` (`make test`) builds every test program,
  runs each in an emulator of its own and gives its report to the
  checker: three timing runs (4,000 frames from stages 1, 6 and 9; a
  late frame fails), the sound driver, the flight stepper in both
  builds, the stage test's six runs, and the play scenes. 17 runs, a
  minute. `run_tests.py timing 4000 -DFIRST_STAGE=6`, `stage 8:6000`,
  `play pause` and the like run a part. Everything is left in
  `build/tests`, a directory a run.
- Checked against the released FS-UAE 3.2.35, which has an older UAE
  core (`run_tests.py --stock`: windows, the Amiga's own speed): the
  sound, flight and stage reports are byte for byte the same in both.
  The timing reports agree on every figure but the sum of all frames'
  lines, which differs by 10 to 30 in half a million, and does so from
  run to run in the same emulator: when the program starts relative to
  the beam depends on the host's disk.
- **The released build is played from outside** (`game.py`,
  `playtest.py`): the test moves the stick, presses the button and keys,
  and reads the game's state by its names. `build/AmiGalaga.dbg` is the
  same program linked with its symbols, which say where `State` is;
  vasm says each field's offset and each constant's value from the
  headers (and `title.s`'s own constants). Nothing in the program is
  there for these tests. The scenes: `menus` (the title, every option,
  a game with six fighters, HARD and four shots in flight), `pause`,
  `attract` (silent throughout, ended by the button and by itself, the
  score put back), `initials` and `floppy` (see Saving). Sound is
  checked by watching the CPU's writes to Paula's volume registers.
- `run_tests.py stress` is not part of `make test`: see Measured budget.
  `run_tests.py stress -DSOMETHING=1` gives every stress build a switch,
  to compare two ways of doing a thing on the same game.
- `game/tools/compat.py` (`make compat`) boots the released disk on
  other Amigas and plays for half a minute: no crash, the title's
  picture pixel for pixel the stock A500's, the game's and the sound's
  speed, something hit and heard, the left mouse button out to the
  prompt and the game started again. 2026-10-02, all as the stock A500:
  A500 with Kickstart 1.2, 1.3 (also with slow RAM and with fast RAM)
  and 2.04, A500+, A600 with 2.05 and 3.1, A1200 with 3.0 and 3.1 (also
  with fast RAM), A4000 with 3.1. An NTSC A500 failed, and is no longer
  in the sweep: the game is PAL only. This is the emulator's word, not
  a real machine's.
- Found by these tests and fixed: `SoundPause` and `SoundInit` cleared
  Paula's volume registers with `clr`, which reads first on a 68000 and
  so writes the bus's garbage to a write-only register for a moment
  (now in the style guide). Found and not fixed: the late frames under
  Open.
- A gap in the stage test's model, found when the fighter was raised
  and a run played out differently: a game that ends with enemies in
  the formation rebuilds their rows' strips that frame (`StageIdle`),
  which holds the one-row-a-frame turn back by a frame; the model did
  not, and from then on could have a landed enemy in its strip a frame
  early. It showed as one dive launched for another enemy. The model
  now does as the game.
- Not usable for timing: `cycle_exact=false` is faster still but gives
  106 lines where the truth is 134.

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

With everything up to the results screen in (2026-10-01), self-playing
runs of 4,000 frames. The report gives the worst frame's number and
lists the late frames with what was on screen
(`tools/run_tests.py timing 4000 -DFIRST_STAGE=6`):

| From stage | Average | Worst frame | Frames over 313 |
|---|---|---|---|
| 1, whole strips copied | 167 | 310 | 0 |
| 6, whole strips copied | 174 | 331 | 6 |
| 1 | 128 | 278 | 0 |
| 6 | 138 | 305 | 0 |
| 9 | 124 | 300 | 0 |

From stage 6 on the game was over budget in its busiest frames (a
busy entrance: 8 to 10 flying, 4 bombs, 1 to 4 explosions). The profile
(`-DPROFILE=1`: where a frame's lines go; the marks cost about 15 lines
a frame themselves, and a blit is paid for in the part after it) showed
that copying the five strips was the largest item, 65 lines a frame,
paid in full even with most of the formation empty or flying. Now only
the part of a strip that has enemies in it is copied (see Rendering):
29 lines on average, and no late frame in these runs. The margin in
the worst frame is 8 lines, so it is still thin.

Average lines from stage 6 after that: formation 29, rebuilding strips
21, drawing the flights 18, logic 17, text and the last flyer blits 16,
erasing flyers 11, shots and hits 9, moving flights 6, sprites and
panel 5, blasts 4, bombs 4. Next candidates, not done: rebuild only
the part of a strip that changes (a rebuild clears and refills the
whole strip), the cheaper bomb, and looking only at the formation's
columns near a shot. Done since: explosions as one 32x32 object, and
the flights placed once a frame (see Stress).

**Stress** (2026-10-02, `tools/run_tests.py stress`). The test builds'
player presses the button every 16 frames. The stress runs play a build
from outside with the button hammered (down every other frame) and the
stick going from side to side, the reserve topped up so the game lasts,
and time every pass of the main loop over 6,000 of them; a pass that
misses a frame is a late frame. So that two builds can be compared, the
same game is played whatever the code costs: the stick and the button go
by the game's own passes, and the beam's position, which the game mixes
into its random numbers, is read as nought there. The scores in the
report say that it was the same game.

Late frames, and the worst frame's lines of work, with what was done
about them:

| Run | As it was | Explosions as one object | and flights placed once a frame |
|---|---|---|---|
| From stage 1, 2 shots | 0 (297) | 0 (291) | 0 (284) |
| From stage 9, 2 shots | 0 (301) | 0 (301) | 0 (283) |
| From stage 9, 4 shots, two fighters | 18 (343) | 11 (335) | 0 (301) |
| From stage 14, 4 shots, two fighters | 16 (354) | 13 (339) | 1 (324) |
| From stage 20, 4 shots, two fighters | 73 (381) | 50 (369) | 9 (333) |

- **Explosions:** a big frame is one 32x32 object, not four flyers (see
  Rendering). The picture is the same: 224 frames with a big explosion
  in them compared between the two.
- **Flights placed once a frame:** where the late frames' lines went was
  measured from outside (breakpoints on the routines a frame calls in
  turn; no marks in the program). The largest item was not drawing: the
  shots' and fighters' hit tests took 83 lines of a 320-line frame,
  because every shot, each arcade frame, worked out where each of up to
  12 flights is (`FlightPlace`, some 280 cycles). Now that is done once
  a frame, when the flights have moved (`fl_px`, `fl_py`), and the hit
  tests and the drawing read it. The stage test is identical, so the
  game is the same. It costs about a line in a quiet frame.
- **The sound driver was looked at and left alone.** With the driver
  switched off altogether the worst frames are 12 to 14 lines shorter,
  so that is all there is to gain. Its own cost over the sound test's
  script (the blitter off, so nothing holds the CPU up) is 3,570 cycles
  a tick; of that the interrupt's coming and going is about 340, the 22
  tests for sounds that are off 480, the tracks 1,020 (304 each), and
  the rest handling and Paula. What can be had without making it harder
  to read (a table for a waveform's address, a pointer carried from
  track to track, testing two sounds at once where their numbers are
  next to each other) comes to 150 to 250 cycles a tick, about a line a
  frame. The larger ideas under Open change how it sounds or what it is.
- What is left in the heaviest frames (stage 20, 11 flying, 7 bombs):
  drawing the flights 70 lines, logic and moving them 47, shots and
  hits 43 (now mostly the formation's columns, ten tests a row in
  reach), the formation 34, erasing 34, bombs 23, strips 22.

The three timing runs, as the code is now: 132 lines on average and 255
at worst from stage 1, 142 and 297 from stage 6, 127 and 281 from
stage 9 (before: 281, 307 and 302 at worst).

With the fighter 10 lines higher the stress runs play other games than
those in the table (what the fighter meets, it meets elsewhere): late
frames 0, 0, 0, 0 and 11, worst frames 303, 269, 291, 285 and 330.

Found and fixed with the profile: building a line of text took about
13 lines a flyer (a byte at a time); it now builds both letters of a
flyer a row at a time, about four times faster, which took the frame
that sets a stage up from 330 lines to under 313. The results' four
lines are built one a frame.

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
  would let the stage test run with capture on. The user knows of the
  gap and has put it off: fix it if something turns out to be amiss
  (2026-10-01). Also open there:
  firing from inside the beam, and the captured fighter that comes back
  in a later stage.
- **Title, second pass:** the arcade's own scripted demonstration, if
  wanted. Entering initials, the pause key, the
  SHOTS option and the attract mode are checked by the play scenes (see
  Tests) but the user has not yet seen them.
- **A few late frames are left in the hardest play** (see Measured
  budget, Stress): none in the self-playing test runs, with 16 lines to
  spare in the worst one, and none with the button hammered and the
  arcade's two shots. With four shots and two fighters: none on stages
  9 to 12, 1 in 6,000 on stages 14 to 16, 9 in 6,000 on stages 20 to
  22. Accepted by the user as it is (2026-10-02): a few late frames
  are better than messy code, and many Amiga games were not this fast.
  No more work on the frame budget is planned.
- **The initials screen is late one frame in 16.** It takes about 265
  lines a frame (the best scores 232, the title 104: six lines of text
  drawn as flyers every frame), and rebuilding the blinking line costs
  another 45 or so. Nothing shows it (the stars are the interrupt's),
  but the 20 seconds of patience are 21.
- **Sound cost: deferred, by decision.** The driver works and the user
  has confirmed it sounds right on the emulated A500 (2026-10-01). At up
  to 19 lines a frame it is the largest CPU item measured, and it lifts
  the worst frame with 20 flyers to 294 of 313 lines. Make it fast later
  ("first work, then fast"). Looked at on 2026-10-02 and left as it is:
  see Stress under Measured budget for what it costs and why. Ideas,
  none tried:
  - test two sounds per instruction by laying the request bytes out in
    handling order;
  - a lighter path for the one-voice sounds (shots, hits, dive), which
    are most of a busy stretch;
  - play some sounds from pre-computed per-tick streams;
  - run two driver steps per interrupt at 60 Hz and write Paula once.
  Any change must still pass `tools/run_tests.py sound`.
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

## Repository

| Path | Contents |
|---|---|
| `game/` | the game itself, written to the style guide: `make`, `make run`, `make test` (see Tests) |
| `game/tools/run_tests.py`, `amiga.py`, `game.py`, `playtest.py`, `compat.py` | the tests: see Tests |
| `experiment-1` .. `experiment-7` | the experiments (1-5 rendering, 6 adds sound, 7 compares blit scheduling); each has `make run`, and `tools/measure.sh` for timing |
| `experiment-1/tools/extract_gfx.py` | sprites, font and palette from the ROM to Amiga bitplanes |
| `analysis/` | MAME Lua trace scripts and results (colours, sprite load, positions) |
| `motion/` | movement extraction, reference stepper, validation against MAME |
| `sound/` | sound extraction, driver and chip model, validation against MAME |
| `docs/style.md` | assembly style guide for the game's code |
| `asmlint/` | the header linter the style guide requires: a standalone Python tool (`uv run pytest` in its directory); the game's build runs it |
| `game/tools/check_rom.py` | run by the build before anything is made from the ROM set: every file the tools read is looked for by name and CRC-32 (the zip's own), and a set that is missing, is not a zip, has other file names (a clone) or other contents (another revision) stops the build with what is wrong and what to do. Tried with each of the four |
| `game/tools/check_even.py` | also run by the build: fails it if a word or long field of a structure in `include/` is at an odd offset (vasm does not align `rs.w`, and a 68000 traps on the access; this happened once and the game came up with a blank screen) |
| `reference/` | local-only reading material, ignored by git |
| `cfg/` | MAME's own settings, written when the arcade is run from here; not ours, untracked |
| `original/` | the user's ROM set, ignored by git |
| `README.md`, `LICENSE` | what the game is and how to build it, for someone new to it; the MIT licence |

Python tooling follows the user's global rules: `uv`, ruff, type hints.
