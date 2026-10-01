# Reference material - local only

Third-party material kept for reading while working on the port. None of
it is ours and none of it may be committed or distributed with the port.

- `hackbar-galaga/`: commented Z80 disassembly of arcade Galaga, cloned
  from https://github.com/hackbar/galaga. It reassembles to the original
  ROM, so treat it exactly like the ROM itself. The repository carries no
  licence file.

Useful entry points: `rom0/gg1-5.s` (sub CPU: flight scripts and the
per-frame motion routine), `rom0/gg1-3.s` (stage data, wave spawner),
`rom0/mrw.s` (RAM layout), `rom0/structs.inc`.

If this project becomes a git repository, ignore `reference/`, `original/`
and every `build/` directory.
