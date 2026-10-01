"""Compare the linter's macro expansion with what vasm itself assembles.

Skipped when vasm is not installed.
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

from asmlint.m68k import is_instruction
from asmlint.reader import read_source
from asmlint.source import Statement, parse_statement

VASM = shutil.which("vasmm68k_mot")

MACROS = """\
SAVED	reg	d2-d3/a2
Count	equr	d5

COPY	macro
	move.\\0	\\1,\\2
	endm

	macro	WAIT
.Wait\\@:
	btst	#6,2(a6)
	bne.s	.Wait\\@
	endm

FILL	macro
	COPY.l	#\\1,d0
	moveq	#\\#,d1
	WAIT
.Fill\\@:
	COPY	d0,(a0)+
	dbf	Count,.Fill\\@
	endm
"""

SOURCE = """\
	include	"macros.i"
Start:
	movem.l	SAVED,-(sp)
	COPY	<8(a0,d0.w)>,d2
	COPY.b	d2,d3
	FILL	$1234,unused
	WAIT
	FILL	0
	movem.l	(sp)+,SAVED
	rts
"""

# A listing line that produced code: section:address, bytes, line number, source.
LISTED = re.compile(r"[0-9A-F]{2}:[0-9A-F]{8} [0-9A-F]+\s+\d+[:M] (.*)")


def instruction(statement: Statement) -> tuple:
    """Return what identifies an instruction, with unique label numbers removed."""
    operands = tuple(re.sub(r"_\d{6}", "_N", operand) for operand in statement.operands)
    return statement.mnemonic, statement.size, operands


@pytest.mark.skipif(VASM is None, reason="vasm is not installed")
def test_expansion_matches_the_vasm_listing(tmp_path: Path):
    (tmp_path / "macros.i").write_text(MACROS)
    (tmp_path / "main.s").write_text(SOURCE)
    subprocess.run(
        [VASM, "-quiet", "-m68000", "-Fbin", "-o", "main.bin", "-L", "main.lst"]
        + ["main.s"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
    )
    listing = (tmp_path / "main.lst").read_text()
    assembled = [
        instruction(parse_statement("main.lst", 0, text))
        for text in LISTED.findall(listing)
    ]

    statements, findings = read_source(tmp_path / "main.s")
    expanded = [instruction(s) for s in statements if is_instruction(s.mnemonic)]
    assert findings == []
    assert len(assembled) == 19
    # The listing shows register aliases as written; the linter resolves them.
    aliases = {"Count": "d5", "SAVED": "d2-d3/a2"}
    resolved = [
        (mnemonic, size, tuple(aliases.get(o, o) for o in operands))
        for mnemonic, size, operands in assembled
    ]
    assert expanded == resolved
