# AmiGalaga

Galaga for the Amiga 500: a port of the 1981 arcade game, written in 68000
assembly for a stock A500 (OCS, 512 KB of chip RAM, Kickstart 1.3, PAL).

It is not an emulation. The enemies fly the arcade's own flight scripts,
arrive in its waves, dive on its schedule and drop bombs by its rules, and
the sound is the arcade's sound driver ported to Paula. Each of those was
checked against the arcade running in MAME. The rest is made for the Amiga:
the formation is drawn as blitter strips, the fighter, its shots and the
stars are hardware sprites, and the game runs at arcade speed on a 50 Hz
display.

**No part of Galaga is in this repository.** The graphics, flight scripts
and sounds are read from your own copy of the arcade ROMs when you build.
See [Bring your own ROM](#bring-your-own-rom).

## What you get

- One player, from PLAYER 1 to GAME OVER: all stages, challenging stages,
  the tractor beam, capture, rescue and the dual fighter, enemies that
  transform, extra fighters at 20,000 and 70,000 and every 70,000 after.
- A title with options: three or six fighters, two to four shots in flight
  at once (two is the arcade's), and the arcade's four difficulty settings.
- The five best scores with initials, saved to disk when you quit.
- An attract mode, and a pause key.

What is not there: coins, credits and the second player.

## Requirements

To run it:

- An Amiga 500 or later, **PAL**, with 512 KB of chip RAM, or an emulator
  set up as one. NTSC machines are not supported: the game runs too fast
  there and the bottom of the screen is cut off.
- A joystick in port 2.

It has been run in emulation on the A500 (Kickstart 1.2, 1.3 and 2.04, with
and without extra memory), A500+, A600, A1200 and A4000. It has not yet been
run on real hardware.

To build it:

- The arcade ROM set, `galaga.zip` (see [Bring your own ROM](#bring-your-own-rom))
- [vasm](http://sun.hasenbraten.de/vasm/) built as `vasmm68k_mot`, and
  [vlink](http://sun.hasenbraten.de/vlink/)
- `xdftool` from [amitools](https://github.com/cnvogelg/amitools), to make
  the disk image
- Python 3.13 or later and [uv](https://docs.astral.sh/uv/)
- `make`

## Bring your own ROM

The game is built from MAME's `galaga` ROM set, the Namco revision B one: a
file called `galaga.zip` with `gg1_1b.3p`, `gg1_9.4l`, `prom-5.5n` and eleven
more files in it. It is not in this repository and you have to supply it.

**Where it goes:** in a directory called `original` at the top of the
repository, beside `game`. The directory is not there in a fresh clone (git
ignores it), so make it:

```sh
cd AmiGalaga                  # the top of the repository, wherever you cloned it
mkdir original
cp /path/to/your/galaga.zip original/galaga.zip
```

which gives:

```
AmiGalaga/
├── README.md
├── game/
│   └── Makefile
└── original/
    └── galaga.zip            <- here
```

Leave it zipped. If you would rather keep the file somewhere else, say where
every time you run make: `make ROM=/path/to/galaga.zip`.

The build checks the set before it makes anything, each file by its name and
checksum. If the file is missing, or is another revision or a clone of the
game (their files have other names, or the same names and other contents),
it stops and says which.

Everything made from the ROM set lands in `build/` directories, which git
ignores. That includes the finished program and disk image: they contain the
arcade's graphics and data, so **do not distribute what you build**.

## Building

With the ROM set in place:

```sh
cd game
make
```

This makes `build/AmiGalaga`, the program, and `build/AmiGalaga.adf`, a
bootable floppy image with the program and its icon on it.

## Running

In [FS-UAE](https://fs-uae.net/), as a stock A500:

```sh
make run                      # or: make run KICK=/path/to/kickstart-1.3.rom
```

On a real Amiga, write `build/AmiGalaga.adf` to a floppy, or put it on a
floppy emulator, and boot from it.

From a hard disk, copy `AmiGalaga` and its icon `AmiGalaga.info` into any
drawer, and start it from Workbench with a double click or from the Shell
by its name.

## Playing

| | |
|---|---|
| Joystick, port 2 | move the fighter; up and down in the menus |
| Fire button | shoot; choose in the menus |
| P | pause, and go on |
| Left mouse button | quit at once |

QUIT on the title gives the machine back to AmigaDOS. The best scores are
written as the game ends, to `AmiGalaga.scores` beside the program, and not
before: they are lost if you switch off without quitting. The game never
touches the disk while it runs.

## How it differs from the arcade

- The screen is 224 pixels wide like the arcade's but 256 lines tall, not
  288. The score, high score, lives and stage badges are in a panel at the
  right, which is where the lines went.
- The fighter is 10 lines higher than the arcade's, so that all of its
  explosion fits on the screen.
- The starfield is the Amiga's own: each star fades by itself.
- With two fighters, four shots and a lot on screen in the late stages, a
  frame is now and then shown twice. With the arcade's two shots it is not.
- A captured fighter whose boss is shot in the formation flies off and does
  not come back in a later stage, and the fighter cannot fire from inside
  the tractor beam.

## Tests

```sh
cd game
make test       # timing, sound, flight, the game against its models, and
                # the released build played from outside: about a minute
make compat     # boot the disk on a dozen other Amigas and play
```

The tests run the game in an emulator and compare what it does with models
that were themselves checked against the arcade in MAME. They need a build of
FS-UAE with Lua scripting, <https://github.com/mwulffn/fs-uae>; see
`game/tools/amiga.py` for where it is looked for.

## Where things are

| Path | Contents |
|---|---|
| `game/` | the game: `src/`, `include/`, `tools/` |
| `motion/` | the arcade's enemy movement: extraction, a reference model, its check against MAME |
| `sound/` | the arcade's sound: extraction, a model of the driver, its check against MAME |
| `analysis/` | MAME scripts that measured what the arcade does |
| `experiment-1` to `experiment-7` | the experiments that settled how to draw and play sound |
| `asmlint/` | a linter that checks every routine's header against its code |
| `docs/style.md` | the assembly style guide |
| `CLAUDE.md` | every decision made, with the measurements behind it |

## Licence

The source code is under the MIT licence: see [LICENSE](LICENSE).

That covers what is in this repository. It does not cover Galaga: the game,
its graphics, sounds and data belong to their owner, and nothing here gives
you any right to them. Galaga is a trademark of Bandai Namco Entertainment
Inc. This project is not affiliated with or endorsed by them.
