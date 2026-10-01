"""Splitting source lines into fields."""

import pytest

from asmlint.source import parse_statement

CASES = [
    # line, label, mnemonic, size, operands
    ("Foo:\tmoveq\t#1,d0", "Foo", "moveq", None, ("#1", "d0")),
    ("Foo\tmoveq\t#1,d0", "Foo", "moveq", None, ("#1", "d0")),
    ("  Foo: rts", "Foo", "rts", None, ()),
    ("Foo::", "Foo", None, None, ()),
    (".Loop:", ".Loop", None, None, ()),
    ("loop$\tbra.s\tloop$", "loop$", "bra", "s", ("loop$",)),
    ("\tMOVE.L\tD0,D1", None, "move", "l", ("D0", "D1")),
    ("\tmove.l\td0,d1 the rest is a comment, really", None, "move", "l", ("d0", "d1")),
    ("\tmove.l\td0, d1", None, "move", "l", ("d0", "d1")),
    ("\tmove.b\t#';',d0\t; real comment", None, "move", "b", ("#';'", "d0")),
    ("\tmove.w\t8(a0,d0.w),(a1)+", None, "move", "w", ("8(a0,d0.w)", "(a1)+")),
    ("\tdc.b\t'a, b',0", None, "dc", "b", ("'a, b'", "0")),
    ("SIZE\tequ\t4", "SIZE", "equ", None, ("4",)),
    ("SIZE = 4", "SIZE", "=", None, ("4",)),
    ("SIZE=4", "SIZE", "=", None, ("4",)),
    ("\tPUSH\t<d0,d1>,x", None, "push", None, ("<d0,d1>", "x")),
    ("* a comment", None, None, None, ()),
    ("; a comment", None, None, None, ()),
    ("", None, None, None, ()),
]


@pytest.mark.parametrize(("line", "label", "mnemonic", "size", "operands"), CASES)
def test_parse_statement(line, label, mnemonic, size, operands):
    statement = parse_statement("test.s", 1, line)
    assert statement.label == label
    assert statement.mnemonic == mnemonic
    assert statement.size == size
    assert statement.operands == operands


def test_comment_text_is_kept():
    statement = parse_statement("test.s", 1, "\tjsr\t(a0)\t; lint: clobbers d0")
    assert statement.comment == " lint: clobbers d0"
    assert not statement.is_comment
    assert parse_statement("test.s", 1, ";--").is_comment
