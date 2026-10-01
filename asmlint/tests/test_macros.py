"""Macros are expanded, so what a macro writes counts for the routine using it."""

HEADER = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: {clobbers}
Foo:
"""


def routine(macros: str, body: str, clobbers: str = "-") -> str:
    """Return macro definitions followed by a routine Foo with the given body."""
    return macros + HEADER.format(clobbers=clobbers) + body


WAITBLIT = """\
WAITBLIT macro
	move.w	#$8400,d0
.Wait\\@:
	btst	#6,2(a6)
	bne.s	.Wait\\@
	endm
"""


def test_register_written_by_a_macro_is_a_write(lint):
    body = "\tWAITBLIT\n\trts\n"
    assert lint(routine(WAITBLIT, body, clobbers="d0")) == []
    assert lint(routine(WAITBLIT, body)) == [
        (
            "main.s:14: error: d0 is written but not listed under Out or Clobbers of Foo"
            " (in macro WAITBLIT)"
        )
    ]


def test_macro_defined_with_the_name_after_the_keyword(lint):
    macros = "\tmacro\tZERO\n\tmoveq\t#0,d0\n\tendm\n"
    assert lint(routine(macros, "\tZERO\n\trts\n")) == [
        (
            "main.s:11: error: d0 is written but not listed under Out or Clobbers of Foo"
            " (in macro ZERO)"
        )
    ]


def test_unique_labels_keep_two_expansions_apart(lint):
    body = "\tWAITBLIT\n\tWAITBLIT\n\trts\n"
    assert lint(routine(WAITBLIT, body, clobbers="d0")) == []


def test_macro_parameters_are_substituted(lint):
    macros = """\
LOAD	macro
	move.\\0	\\1,\\2
	endm
"""
    body = """\
	LOAD.l	d0,d3
	LOAD	<4(a0,d0.w)>,d4
	LOAD	d0,(a1)+
	rts
"""
    assert lint(routine(macros, body, clobbers="d3")) == [
        (
            "main.s:12: error: d4 is written but not listed under Out or Clobbers of Foo"
            " (in macro LOAD)"
        ),
        (
            "main.s:13: error: a1 is written but not listed under Out or Clobbers of Foo"
            " (in macro LOAD)"
        ),
    ]


def test_macros_may_use_other_macros(lint):
    macros = """\
ZERO	macro
	moveq	#0,\\1
	endm
ZERO2	macro
	ZERO	\\1
	ZERO	\\2
	endm
"""
    body = "\tZERO2\td1,d2\n\trts\n"
    assert lint(routine(macros, body, clobbers="d1")) == [
        (
            "main.s:15: error: d2 is written but not listed under Out or Clobbers of Foo"
            " (in macro ZERO2)"
        )
    ]


def test_macro_names_are_case_sensitive(lint):
    macros = "ZERO\tmacro\n\tmoveq\t#0,d0\n\tendm\n"
    assert lint(routine(macros, "\tzero\n\trts\n")) == [
        "main.s:11: error: unknown instruction, directive or macro 'zero'"
    ]


def test_macro_from_an_include_file(lint):
    source = routine('\tinclude\t"macros.i"\n', "\tWAITBLIT\n\trts\n")
    assert lint(source, macros_i=WAITBLIT) == [
        (
            "main.s:9: error: d0 is written but not listed under Out or Clobbers of Foo"
            " (in macro WAITBLIT)"
        )
    ]


def test_annotation_inside_a_macro(lint):
    macros = """\
CALLLIB	macro
	jsr	_LVO\\1(a6)		; lint: clobbers d0-d1/a0-a1
	endm
"""
    body = "\tCALLLIB\tForbid\n\trts\n"
    assert lint(routine(macros, body, clobbers="d0-d1/a0-a1")) == []


def test_annotation_on_a_macro_call_covers_its_whole_expansion(lint):
    macros = """\
SETUP	macro
	lea	State,a5
	lea	$dff000,a6
	endm
"""
    plain = routine(macros, "\tSETUP\n\trts\n", clobbers="a5-a6")
    assert lint(plain) == [
        "main.s:12: error: reserved register a5 is written in Foo (in macro SETUP)",
        "main.s:12: error: reserved register a6 is written in Foo (in macro SETUP)",
    ]
    trailing = routine(macros, "\tSETUP\t; lint: allow a5-a6\n\trts\n", "a5-a6")
    assert lint(trailing) == []
    before = routine(macros, "\t; lint: allow a5-a6\n\tSETUP\n\trts\n", "a5-a6")
    assert lint(before) == []


def test_unknown_mnemonic_is_an_error(lint):
    source = routine("", "\tFROB\td0\n\tbfextu\td0{1:2},d1\n\trts\n")
    assert lint(source) == [
        "main.s:8: error: unknown instruction, directive or macro 'FROB'",
        "main.s:9: error: unknown instruction, directive or macro 'bfextu'",
    ]


def test_unsupported_macro_escape_is_an_error(lint):
    macros = "ODD\tmacro\n\tmoveq\t#\\?1,d0\n\tendm\n"
    source = routine(macros, "\tODD\tabc\n\trts\n", clobbers="d0")
    assert lint(source) == [
        "main.s:11: error: cannot expand '\\?' in macro ODD",
    ]


def test_macro_that_emits_data_outside_routines(lint):
    source = """\
TEXT	macro
	dc.b	\\1,0
	even
	endm
Message:
	TEXT	<'hello, world'>
"""
    assert lint(source) == []


def test_macro_call_on_the_line_of_the_routine_label(lint):
    source = """\
ZERO	macro
	moveq	#0,d0
	endm
;--
; Foo
; In:       -
; Out:      d0 = 0
; Clobbers: -
Foo:	ZERO
	rts
"""
    assert lint(source) == []


def test_macro_without_end_is_an_error(lint):
    source = "ZERO\tmacro\n\tmoveq\t#0,d0\n"
    assert lint(source) == ["main.s:1: error: macro ZERO has no endm"]


def test_recursive_macro_is_an_error(lint):
    source = """\
COUNT	macro
	ifgt	\\1
	dc.b	\\1
	COUNT	\\1-1
	endc
	endm
Table:
	COUNT	3
"""
    assert lint(source) == [
        (
            "main.s:8: error: macro COUNT is expanded more than 50 levels deep;"
            " recursive macros are not supported"
        )
    ]
