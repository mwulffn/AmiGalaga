# Galaga for the Amiga: assembly style guide

These are general guidelines, agreed with Michael on 2026-10-01. The
project specifics (file names, sprite allocation, measurements) belong in
`CLAUDE.md`, not here.

## Target
- Stock OCS A500 with 512 KB of chip RAM, PAL, 68000. Anything faster
  only adds idle time.
- Every part of the game is timed by hardware clocks (the vertical blank
  and a CIA timer), never by how fast the CPU runs.
- 68000 only: assemble with `-m68000`, no 68020 instructions or
  addressing modes, no word or long access at an odd address.
- No self-modifying code. Copper lists are data and do not count.

## Files and linking
- One subsystem per file. The file is the section, so no single growing
  source file.
- Assemble separate objects with vasm and link them with vlink.
- Each file exports labels only with `xdef` and imports only with `xref`.
  Everything else stays private to its file.
- Hardware register names, the state layout and macros live in shared
  include files.
- Operating system calls live in the startup file and nowhere else.

## Sections
- Every file uses the same section name for each type, so vlink merges
  them into a few hunks. This is not only tidiness: Kickstart 1.3 resolves
  PC-relative references only inside one hunk, so `bsr` and `Name(pc)`
  across files work only because the sections merge.
- Only data the custom chips read or write goes in chip-RAM (`_C`)
  sections: screen buffers, copper lists, sprite data, audio samples, and
  everything the blitter reads, including bob images and masks.
- Code, tables and state go in ordinary sections, so they load into fast
  RAM when a machine has it.

## Registers
- Two global registers are reserved and never clobbered. A6 always holds
  `$dff000`. A5 always holds the game-state base, so state is accessed as
  `Name(a5)` through the offsets in the state include, not as absolute
  long addresses.
- Exceptions: startup and shutdown code may use A6 for a library base.
  Interrupt handlers load A5 and A6 themselves and do not trust what
  they find there.
- `Name(a5,d0.w)` reaches only 127 bytes from A5. Index an array in the
  state through a `lea`.
- Any register a routine doesn't declare is preserved. A register passed
  in and changed counts as clobbered unless it is listed under Out.
- Condition codes are never preserved unless Out says so
  (`Out: Z = found`).
- Keep stack pushes to a minimum. An interrupt handler saves the
  registers it uses, once. A routine that borrows extra registers saves
  and restores them itself.

## Routine header
Every routine starts with a header like this:

```
;--
; RoutineName
; In:       d0 = ..., a0 = ...
; Out:      d0 = ...
; Clobbers: d1, a1
```

- All three fields are always present. Write `-` when a field is empty.
  An interrupt handler writes `Clobbers: -`.
- A linter checks the header against the code, so a header that has
  drifted out of date breaks the build. It follows calls (a routine
  inherits the clobbers of what it calls) and sees through macros. It is
  conservative: any register written and not declared is an error.
- The linter is `asmlint/`. Where it cannot know, say so with a comment:
  `; lint: clobbers d0-d1/a0-a1` on a call it cannot follow (a library
  call, a jump through a register), `; lint: targets A, B` for a jump
  table, and `; lint: allow a5, a6` in the header of a routine that may
  write a reserved register. See its README.

## Surface style
- Follow current practice rather than period habits: named constants,
  structures defined with `rsreset`/`rs`, macros with unique local labels
  (`\@`), and nothing that only an old assembler needed.
- Lowercase mnemonics. Write an explicit size wherever the instruction
  takes one (`move.w`, `add.l`). `lea`, `moveq`, `Scc` and bit operations
  on registers take none.
- Write branches without a size (`bne`, `bra`, `bsr`) and let vasm's
  optimiser pick the shortest form. Give a size only where it matters,
  for example in timed code.
- Names:
  - labels and state fields are CamelCase (`DrawFlyers`, `ShipX(a5)`);
  - use local labels (`.Loop`) wherever possible; a label is global only
    if another routine or file needs it;
  - constants and macros are UPPER_CASE (`ROW_BYTES`, `WAITBLIT`);
  - structure offsets are lowercase with a prefix for the structure
    (`t_clock`);
  - hardware registers use Commodore's names in lowercase (`bltcon0`).
- No magic numbers for hardware bits or state values. Name them.
- No banner dividers. `;--` plus the header is enough.
- Comments explain why, not what. Write maths as pseudocode above the
  code that implements it.

## Hardware habits
- Wait for the blitter before starting a blit, never after it. On a
  machine with fast RAM the CPU then keeps working while the blitter
  runs. Two more waits are required for correctness: before the CPU reads
  or writes memory that a pending blit touches, and before a buffer is
  shown.
- The blitter has one owner at a time. Nothing in an interrupt starts a
  blit unless that interrupt is the owner.
- Use an interrupt for work that belongs to a hardware moment (the
  vertical blank, the sound timer). Keep handlers short, and acknowledge
  the request before returning.
- Moving work into an interrupt is a change to measure, like any other.
  A blitter-finished interrupt that starts the next blit from a queue is
  a candidate: it frees the CPU on machines with fast RAM, and costs an
  interrupt per blit on a stock A500. Not adopted until measured.
- Choose blitter priority by measuring it, and measure again whenever
  the CPU load changes.
- Keep compile-time switches in a single config include. Put debug aids
  such as the raster meter behind a switch that is off in release builds.
