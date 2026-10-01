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
| `trace_noise.lua` | MAME script: silences the tone chip and logs every explosion command, for use with `-wavwrite` |
| `noise_analyse.py` | cuts the explosions out of that recording into `build/noise/` and measures them (needs numpy) |
| `noise_match.py` | builds our own explosion to match, as an ideal version and two Amiga versions, with a comparison WAV |

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

Enemy hits are tones from this chip. The one sound that is not is the
fighter's own explosion: request `$19` makes the main CPU send a four-byte
command to a separate noise generator.

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

## The fighter explosion

Recorded from MAME with the tone chip silenced (15 instances, including
the one in the power-on sound test):

    mame galaga -rompath ../original -video none -sound none -samplerate 48000 \
        -wavwrite noise.wav -nothrottle -skip_gameinfo -autoboot_script trace_noise.lua
    uv run --with numpy python3 noise_analyse.py noise.wav noise_events.txt build/noise

- It is the only noise sound in the game, always sent with the same
  parameters, and the instances differ by 2% in loudness.
- It lasts about 2.7 seconds: full level for the first fifth of a second,
  then it halves about every half second until it is cut off.
- It is a low rumble. 96% of its energy is between 100 and 800 Hz, half
  of it below about 260 Hz, and almost nothing above 1600 Hz.

The recordings are MAME's output and are for listening and measuring only.

`noise_match.py` builds an explosion of our own to those measurements,
from random noise shaped to the measured spectrum and decay, and writes
it next to the reference for comparison (`build/noise/compare.wav`):

    uv run --with numpy python3 noise_match.py build/noise

It makes two Amiga versions at 4 kHz, 8 bits: the whole sound as one
sample (about 11 KB), and a 2 KB loop whose decay is done with Paula's
volume register once per frame. Both come out within a few percent of
the reference in spectrum and loudness over time.

## Not done yet

- The Amiga player, and the choice between porting the driver logic and
  playing back streams.
- The sound names are from the reference disassembly's comments and from
  where the main CPU sets each request. The user has listened to all 23
  and they sound right; the names themselves are not all confirmed.
- Each one-shot is recorded with a count of 1, so repeating sounds are
  shorter here than in the game.
