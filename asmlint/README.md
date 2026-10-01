# asmlint

A linter for Motorola 68000 assembly source in vasm's Motorola syntax. It
compares the header comment of every routine with what the routine's code
does to the registers, so a header that has drifted out of date is found
before it causes a bug.

It is plain Python with no runtime dependencies. It reads the source
directly, so it needs neither vasm nor a build.

## The header

Every routine starts with a header:

```
;--
; RoutineName
; In:       d0 = ..., a0 = ...
; Out:      d0 = ...
; Clobbers: d1, a1
RoutineName:
```

- The header is a line holding only `;--`, followed by comment lines: the
  routine name, then the fields `In:`, `Out:` and `Clobbers:`. All three
  fields are required; `-` means empty.
- `In` and `Out` are free text. A register counts as named there when it
  is followed by `=` (`d0.w = count`, `a0/a1 = pointers`) or stands alone
  between commas. Anything else is prose, so `Out: Z = found` is fine.
  Condition codes are not tracked.
- `Clobbers` is `-` or register lists separated by commas: `d1, a1` or
  `d0-d2/a0`. `sp` means `a7`.
- A field may continue on the next comment line if that line is indented
  by two or more spaces. Other comment lines in the header are ignored, so
  a description may follow the fields.
- The next label after the header must be the name the header gives.
- A routine runs from its header to the next header or the end of the
  file. Local labels (`.name` or `name$`) belong to the global label
  before them.

## What it checks

Errors:

- A routine without a header (code before the first header of a file, or
  a global label that nothing in its routine reaches), a header without a
  name or without one of the three fields, an empty field, a `Clobbers`
  field that cannot be parsed, and a header whose name is not the label
  that follows.
- A register (d0-d7, a0-a7) that the routine may change and that is not
  listed under `Out` or `Clobbers`. This includes registers named under
  `In`. "May change" means that on some path through the routine the
  register does not hold its entry value when the routine returns.
- Registers changed by the routines it calls. A `bsr`, `jsr`, `bra` or
  `jmp` to another routine inherits everything that routine lists under
  `Out` and `Clobbers`. So does falling through into the next routine.
  Routines are looked up in the same source file first (with its include
  files), then among the other files given on the command line, where
  routines exported with `xdef` come before plain global labels.
- Calls that cannot be analysed and are not annotated: a call to a label
  that is not a routine with a header, an indirect `jsr (a0)` or
  `jmp (a0)`, a `trap`.
- A stack that is not balanced when the routine returns, unless `a7` is
  listed under `Out` or `Clobbers`.
- A write to a reserved register (by default a5 and a6) without an
  annotation that allows it, even if the register is saved and restored.
  Calling a routine that changes a reserved register counts as a write.
- In an interrupt handler (a routine that ends in `rte`): any register not
  restored, and a `Clobbers` field that is not `-`.
- Code the linter cannot follow: an unknown instruction or macro, a branch
  to a label that does not exist, execution running into data or off the
  end of the file, a `movem` whose register list it cannot read.

Warnings:

- A register listed under `Out` or `Clobbers` that the routine never
  changes (a stale header).
- Unreachable code, which is not checked.

A register that the routine saves with a long push and restores with a
long pop counts as preserved: `movem.l d2-d3/a2,-(sp)` with
`movem.l (sp)+,d2-d3/a2`, or `move.l d2,-(sp)` with `move.l (sp)+,d2`.
`link`/`unlk` preserve the frame pointer. The linter follows every path
through the routine, so each exit may restore for itself, and an exit that
skips the restore is found.

The instruction table knows which operand each 68000 instruction writes,
including the implicit ones: the counter of `dbcc`, the address register
of `(an)+` and `-(an)` in any operand, both operands of `exg`, the
registers of `movem`, and so on. Writes to memory are not register writes.

## Annotations

An annotation is a comment of the form `; lint: keyword arguments`.

| Annotation | Meaning |
| --- | --- |
| `; lint: clobbers d0-d1/a0` | The call or jump on this line changes exactly these registers (`-` for none). For calls the linter cannot analyse: indirect calls and jumps, unknown routines, traps. |
| `; lint: targets Foo, Bar, .Case` | The indirect call or jump on this line goes to one of these labels. Routines are inherited from; labels inside the routine are followed, which is how a jump table is described. |
| `; lint: allow a5, a6` | These reserved registers may be written. |

Where an annotation applies:

- At the end of an instruction line, it applies to that instruction.
- On a comment line of its own, it applies to the next instruction.
- On (or before) a macro call, it applies to every instruction of that
  macro's expansion. Annotations may also be written inside a macro.
- In a routine header, only `allow` is permitted, and it applies to the
  whole routine. This is meant for startup code and interrupt handlers.

```
;--
; VBlank
; In:       -
; Out:      -
; Clobbers: -
; lint: allow a5-a6
VBlank:
	movem.l	d0/a5-a6,-(sp)
	lea	State,a5
	lea	$dff000,a6
	...
	movem.l	(sp)+,d0/a5-a6
	rte

	move.l	4.w,a6			; lint: allow a6
	jsr	_LVOForbid(a6)		; lint: clobbers d0-d1/a0-a1

	jmp	.Table(pc,d0.w)		; lint: targets .Idle, .Dive, .Return
```

An allowed write to a reserved register still follows the normal rules:
the register must be restored or be listed under `Out` or `Clobbers`.

## Running it

```
uv run asmlint [-I DIR]... [--reserved REGISTERS] FILE...
```

- Give all the source files of the program in one run, so that calls
  across files can be followed. Include files are read through the
  `include` directives and should not be listed.
- `-I DIR` adds a directory to search for include files. A file is also
  looked for next to the file that includes it, in the current directory,
  and in directories named by `incdir`.
- `--reserved a4,a5` sets the reserved registers; `--reserved -` means
  none. The default is `a5,a6`.

Output is one line per finding, `file:line: severity: message`, sorted by
file and line. A finding in code that comes from a macro is reported at
the line that uses the macro and names the macro. The exit status is 0
when there are no errors (warnings do not count), 1 when there are errors
and 2 when the linter could not run.

From Python: `asmlint.lint_files(paths, reserved=..., include_dirs=...)`
returns the list of findings.

Development:

```
uv sync
uv run pytest
uv run ruff format .
uv run ruff check .
```

## Macros: source parsing, not listing files

A routine that uses a macro which writes d0 clobbers d0, so the linter has
to see through macros. There were two ways to do that: lint a vasm listing
file (`-L`), in which vasm has expanded the macros, or parse the macro
definitions and expand them in the linter. The linter parses the source.

A listing has one real advantage: vasm does the expansion, so it cannot
differ from what is assembled. It loses on everything else:

- A listing shows one build configuration. Lines in a conditional branch
  that was not assembled appear without code, so a header could be wrong
  in the debug build and pass in the release build. Parsing the source
  checks every branch.
- It needs a successful assembly first, with the right options for each
  file, so it cannot run on code that does not build yet or in an editor.
- The listing format is not a documented interface and may change between
  vasm versions. Source positions have to be reconstructed from it.
- The tests would need vasm, or listings pasted in as fixtures.

The cost is that the linter has its own small macro processor. It
supports what the style it checks uses: `NAME macro` and `macro NAME`,
`endm`, the parameters `\1` to `\9`, `\0` (the size given on the call,
`w` by default), `\#` (the number of arguments), `\@` (a unique label
suffix), arguments in `<...>`, and macros that use other macros. Anything
else is reported as an error rather than guessed at. When vasm is
installed, a test assembles a sample and compares vasm's listing with the
linter's expansion, instruction by instruction.

What follows from parsing the source:

- **Include files** are read where they are included, so their macros,
  register aliases and routines are seen. A file is read once per source
  file, even if it is included again. A missing include file is an error.
- **Conditional assembly** (`if`, `ifeq`, `ifne`, `ifd`, `ifnd`, `ifc`,
  ..., `else`, `elseif`, `elif`, `endc`, `endif`) is not evaluated. The
  linter checks a routine once for every combination of outcomes of the
  conditions in it, so the header must hold in every configuration.
  Conditionals that test the same thing (`ifd DEBUG` twice, or
  `ifd DEBUG` and `ifnd DEBUG`, or `if X` and `ifeq X`) are taken
  consistently. A routine with more than eight different conditions is
  checked once, with every conditional going both ways.
- `equr` and `reg` aliases are resolved. The body of `rept` is checked
  once. `rem`/`erem` blocks are skipped and `end` ends a file.

## Known limitations

Things that are reported although the code may be correct:

- Every configuration of conditional assembly is checked, including
  combinations that are never built. Two conditions that are written
  differently are treated as independent, even if they always agree.
- Only saves through the stack count. A register saved in another
  register or in memory and restored later must be listed as clobbered.
  A word-sized push and pop does not preserve a register.
- The stack model is simple. Each path must leave the stack as it found
  it; pushing in a loop, popping the return address, or returning through
  an address pushed with `pea` is reported as an unbalanced stack. Space
  reserved with a named size (`lea -FRAME(sp),sp`) must be released with
  exactly the same expression.
- A register listed under `Out` that the routine passes through unchanged
  gets the stale-header warning.
- A routine with a second entry point can only be called through that
  entry if the entry has a header of its own. A `bsr` to a local label is
  an error for the same reason.
- Unreachable code is only warned about, never analysed. Code reached
  through a jump table needs a `targets` annotation.
- Recursive macros, macro features other than those listed above, `iif`
  and 68020+ instructions are reported as errors.

Things that are not noticed:

- At a call, the linter trusts the header of the routine called. That
  routine's own check is what verifies it, so a wrong header is reported
  there, not at the call.
- Condition codes, and whether `Out` flags are really set.
- A saved register overwritten on the stack through another address
  register (`move.l sp,a0` ... `move.l d0,(a0)`). Writes through `sp`
  itself are seen.
- Exceptions: `chk`, `trapv` and a division by zero are not followed.
- A symbol redefined between two conditionals that test it, and a macro
  defined more than once (the last definition before a use is the one
  expanded, as in vasm, but both branches of a conditional define it).
- `mexit` is ignored: the rest of the macro is treated as if it ran.
- A label defined twice in one routine (in two branches of a conditional)
  resolves to the last definition.
- A macro with the name of a vasm directive is expanded by the linter,
  while vasm runs the directive.

Other notes:

- The operand field ends at the first blank, as in vasm without
  `-spaces`; only a blank straight after a comma is tolerated.
- Only vasm's Motorola syntax and the 68000 instruction set are known.
