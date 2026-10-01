"""Which registers each 68000 instruction writes."""

import pytest

from asmlint.m68k import INSTRUCTIONS, is_instruction, written_registers
from asmlint.source import parse_statement

CASES = [
    # moves
    ("move.l d0,d1", "d1"),
    ("move.w d0,(a0)", ""),
    ("move.w (a0)+,d1", "a0 d1"),
    ("move.b d0,-(a1)", "a1"),
    ("move.w (a0)+,(a1)+", "a0 a1"),
    ("move.w 4(a0),8(a1,d0.w)", ""),
    ("move.l d0,a2", "a2"),
    ("movea.l d0,a2", "a2"),
    ("move.w d0,ccr", ""),
    ("move.w d0,sr", ""),
    ("move.w sr,d0", "d0"),
    ("move.l a0,usp", ""),
    ("move.l usp,a0", "a0"),
    ("moveq #1,d7", "d7"),
    ("move.l #Label,d3", "d3"),
    ("move.l d0,Label", ""),
    ("move.l d0,$dff180", ""),
    ("move.l D0,D1", "d1"),
    ("move.l d0,sp", "a7"),
    ("movep.w d0,0(a0)", ""),
    ("movep.w 0(a0),d0", "d0"),
    # movem in both directions
    ("movem.l d0-d2/a0,(a1)", ""),
    ("movem.l d0-d2/a0,-(a1)", "a1"),
    ("movem.l (a1),d0-d2/a0", "d0 d1 d2 a0"),
    ("movem.w (a1)+,d3/d5", "a1 d3 d5"),
    ("movem.l (a1)+,d3", "a1 d3"),
    ("movem.l d3,(a1)", ""),
    # arithmetic and logic
    ("add.w d0,d1", "d1"),
    ("add.w d0,(a1)", ""),
    ("adda.l d0,a1", "a1"),
    ("addi.w #1,d1", "d1"),
    ("addq.l #1,a3", "a3"),
    ("addq.w #1,(a3)", ""),
    ("addx.l d0,d1", "d1"),
    ("addx.l -(a0),-(a1)", "a0 a1"),
    ("sub.w d0,d1", "d1"),
    ("suba.l d0,a1", "a1"),
    ("subi.w #1,d1", "d1"),
    ("subq.w #1,d1", "d1"),
    ("subx.l d0,d1", "d1"),
    ("and.w d0,d1", "d1"),
    ("andi.w #1,d1", "d1"),
    ("andi.w #$f8ff,sr", ""),
    ("or.w d0,d1", "d1"),
    ("ori.b #1,d1", "d1"),
    ("ori.b #1,ccr", ""),
    ("eor.w d0,d1", "d1"),
    ("eori.w #1,d1", "d1"),
    ("mulu.w d0,d1", "d1"),
    ("muls.w (a0)+,d1", "a0 d1"),
    ("divu.w d0,d1", "d1"),
    ("divs.w #3,d1", "d1"),
    ("abcd d0,d1", "d1"),
    ("sbcd -(a0),-(a1)", "a0 a1"),
    ("nbcd d1", "d1"),
    ("neg.w d1", "d1"),
    ("negx.w d1", "d1"),
    ("not.w d1", "d1"),
    ("not.w (a1)", ""),
    ("clr.l d1", "d1"),
    ("clr.w (a0)+", "a0"),
    ("ext.l d2", "d2"),
    ("swap d2", "d2"),
    ("tas d2", "d2"),
    ("exg d0,a1", "d0 a1"),
    ("lea 4(a0),a1", "a1"),
    ("lea Label(pc),a1", "a1"),
    ("pea 4(a0)", ""),
    # shifts and rotates
    ("asl.w #1,d1", "d1"),
    ("asr.w d0,d1", "d1"),
    ("lsl.w #1,d1", "d1"),
    ("lsr.w d1", "d1"),
    ("lsr.w (a1)", ""),
    ("rol.w #1,d1", "d1"),
    ("ror.w #1,d1", "d1"),
    ("roxl.w #1,d1", "d1"),
    ("roxr.w #1,d1", "d1"),
    # bit operations
    ("bset #1,d1", "d1"),
    ("bclr d0,d1", "d1"),
    ("bchg #1,d1", "d1"),
    ("bset #1,(a1)", ""),
    ("btst #1,d1", ""),
    # compares and tests write nothing, except through the addressing mode
    ("tst.w d1", ""),
    ("tst.w (a1)+", "a1"),
    ("cmp.w d0,d1", ""),
    ("cmpa.l d0,a1", ""),
    ("cmpi.w #1,d1", ""),
    ("cmpm.b (a0)+,(a1)+", "a0 a1"),
    ("chk.w d0,d1", ""),
    # set on condition
    ("st d1", "d1"),
    ("sf d1", "d1"),
    ("seq d1", "d1"),
    ("sne (a1)", ""),
    ("shi d1", "d1"),
    ("sls d1", "d1"),
    ("scc d1", "d1"),
    ("scs d1", "d1"),
    ("shs d1", "d1"),
    ("slo d1", "d1"),
    ("svc d1", "d1"),
    ("svs d1", "d1"),
    ("spl d1", "d1"),
    ("smi d1", "d1"),
    ("sge d1", "d1"),
    ("slt d1", "d1"),
    ("sgt d1", "d1"),
    ("sle d1", "d1"),
    # loops write their counter
    ("dbf d1,.Loop", "d1"),
    ("dbra d1,.Loop", "d1"),
    ("dbeq d1,.Loop", "d1"),
    ("dbne d1,.Loop", "d1"),
    ("dbcc d1,.Loop", "d1"),
    ("dbmi d1,.Loop", "d1"),
    # stack frames
    ("link a4,#-8", "a4"),
    ("unlk a4", "a4"),
    # flow and system instructions write nothing themselves
    ("bra .Loop", ""),
    ("bne.s .Loop", ""),
    ("bsr Other", ""),
    ("jsr Other", ""),
    ("jmp (a0)", ""),
    ("rts", ""),
    ("rte", ""),
    ("rtr", ""),
    ("nop", ""),
    ("stop #$2000", ""),
    ("reset", ""),
    ("trap #0", ""),
    ("trapv", ""),
    ("illegal", ""),
]


@pytest.mark.parametrize(("code", "expected"), CASES)
def test_written_registers(code, expected):
    statement = parse_statement("test.s", 1, f"\t{code}")
    assert is_instruction(statement.mnemonic)
    assert written_registers(statement) == set(expected.split())


def test_pushes_and_pops_are_not_register_writes():
    for code in ("move.l d0,-(sp)", "move.l (sp)+,d0", "pea (a0)", "clr.w -(a7)"):
        statement = parse_statement("test.s", 1, f"\t{code}")
        assert written_registers(statement) <= {"d0"}


@pytest.mark.parametrize("mnemonic", ["section", "dc", "frobnicate", "bfextu", None])
def test_other_mnemonics_are_not_instructions(mnemonic):
    assert not is_instruction(mnemonic)


OPERANDS = [
    "",
    "d0",
    "(sp)+",
    "d0,-(sp)",
    "#4,sp",
    "a4,#-8,d1",
    "(a0)+,d0-d1/a5",
    ",",
    "x",
]


@pytest.mark.parametrize("operands", OPERANDS)
def test_malformed_instructions_do_not_crash_the_linter(lint, operands):
    header = ";--\n; Foo\n; In: -\n; Out: -\n; Clobbers: -\nFoo:\n"
    body = "".join(f"\t{mnemonic}\t{operands}\n" for mnemonic in sorted(INSTRUCTIONS))
    body += "".join(f"\t{name}\t{operands}\n" for name in ("if", "else", "macro", "x"))
    lint(header + body)
    for mnemonic in sorted(INSTRUCTIONS):
        lint(header + f"\t{mnemonic}\t{operands}\n\trts\n")
