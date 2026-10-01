# Sound

How the arcade makes its sound, and tools to pull it out of the user's own
ROM set (Namco rev. B `galaga.zip`). Nothing in this directory contains
ROM data; everything under `build/` is generated and must not be committed
or distributed.

    uv run --with z80 python3 extract.py ../original/galaga.zip build

| File | What it is |
|---|---|
| `galaga_sound.py` | the sound driver (the arcade's own program in a Z80 emulator), the sound chip model, the list of sounds |
| `extract.py` | plays every sound on its own; writes `build/wav/`, `build/stream/`, `build/waves.bin`, `build/sounds.txt` |
| `trace_sound.lua` | MAME script: plays the game and logs every sound driver tick |
| `validate.py` | replays a trace through the driver and compares what it writes to the chip |

## How the arcade does it

A third Z80 does nothing but sound. 121 times a second (twice per video
frame) it reads a block of request bytes that the game sets, one per
sound, advances the sounds that are playing, and writes frequency, volume
and waveform for three voices to the sound chip.

The chip is a wavetable player: each voice steps through one of eight
32-sample waveforms (in a PROM) at a programmable rate and volume.

There are 23 sounds. Most are one-shots; a request byte holds a count, so
the game can ask for a sound several times over (the extra-fighter jingle
is requested with 7). Six are on for as long as their request is set: the
pulsing formation sound, the two tractor beam sounds, the rescue theme and
two others. Sounds are processed in a fixed order each tick and later ones
overwrite the voices of earlier ones; that is the whole of the mixing.

Explosions do not come from this chip. Request `$19` goes to a separate
noise generator, which is not modelled here.

## The model

`Driver` loads the sound ROM into a Z80 emulator and calls the interrupt
handler once per tick, so its behaviour is the arcade's by construction.
It is a reference and an extraction tool, not something to port: the Amiga
needs either its own port of the driver logic, or to play back the
per-tick streams this produces.

`validate.py` against 40,000 frames of MAME (stages 1 to about 9): all
78,575 ticks produce identical chip writes. The trace has to record what
the sound CPU actually read during each tick; a snapshot taken at the
start of the tick misses requests the main CPU sets a moment later.

`render()` models the chip from MAME's source (96 kHz, 20-bit phase, top
five bits index the waveform). It has not been compared with MAME's audio
output, so the WAV files are for listening, not a reference.

## What the extraction shows

See `build/sounds.txt`. One-shot sounds total about 36 seconds. Every
sound stays between 94 and 2143 Hz. Paula tops out near 28 kHz, so the
32-sample waveforms reach about 875 Hz; `waves.bin` therefore also holds
16-, 8- and 4-sample copies, and no sound needs shorter than 8.

## Not done yet

- The noise generator (explosions).
- The Amiga player, and the choice between porting the driver logic and
  playing back streams.
- The sound names are from the reference disassembly's comments and from
  when each request appears in a game; they have not been confirmed by
  listening. `sound_09` is unidentified.
- Each one-shot is recorded with a count of 1, so repeating sounds are
  shorter here than in the game.
