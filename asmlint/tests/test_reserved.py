"""Reserved registers may not be written unless an annotation allows it."""

HEADER = """
;--
; Foo
; In:       -
; Out:      -
; Clobbers: {clobbers}
"""


def routine(body: str, clobbers: str = "-", annotation: str = "") -> str:
    """Return a routine Foo; without an annotation the body starts on line 8."""
    return HEADER.format(clobbers=clobbers) + annotation + "Foo:\n" + body


def test_writing_a_reserved_register_is_an_error_even_when_declared(lint):
    source = routine(
        """\
	lea	Table,a5
	move.w	(a6)+,d0
	rts
""",
        clobbers="d0/a5-a6",
    )
    assert lint(source) == [
        "main.s:8: error: reserved register a5 is written in Foo",
        "main.s:9: error: reserved register a6 is written in Foo",
    ]


def test_saving_and_restoring_does_not_excuse_a_reserved_write(lint):
    source = routine("""\
	move.l	a6,-(sp)
	move.l	4.w,a6
	move.l	(sp)+,a6
	rts
""")
    assert lint(source) == ["main.s:9: error: reserved register a6 is written in Foo"]


def test_restoring_a_reserved_register_is_not_a_write(lint):
    source = routine("""\
	movem.l	d2/a6,-(sp)
	moveq	#0,d2
	movem.l	(sp)+,d2/a6
	rts
""")
    assert lint(source) == []


def test_header_annotation_allows_writes_in_the_whole_routine(lint):
    body = """\
	lea	State,a5
	lea	$dff000,a6
	rts
"""
    source = routine(body, clobbers="a5/a6", annotation="; lint: allow a5, a6\n")
    assert lint(source) == []
    source = routine(body, annotation="; lint: allow a5, a6\n")
    assert lint(source) == [
        "main.s:9: error: a5 is written but not listed under Out or Clobbers of Foo",
        "main.s:10: error: a6 is written but not listed under Out or Clobbers of Foo",
    ]


def test_line_annotation_allows_one_instruction(lint):
    source = routine(
        """\
	lea	State,a5		; lint: allow a5
	; lint: allow a6
	lea	$dff000,a6
	lea	Other,a5
	rts
""",
        clobbers="a5/a6",
    )
    assert lint(source) == ["main.s:11: error: reserved register a5 is written in Foo"]


def test_call_that_clobbers_a_reserved_register(lint):
    init = """
;--
; Init
; In:       -
; Out:      a5 = state
; Clobbers: -
; lint: allow a5
Init:
	lea	State,a5
	rts
"""
    body = "\tbsr\tInit\n\trts\n"
    assert lint(routine(body, clobbers="a5") + init) == [
        "main.s:8: error: reserved register a5 is clobbered by the call to Init in Foo"
    ]
    body = "\tbsr\tInit\t; lint: allow a5\n\trts\n"
    assert lint(routine(body, clobbers="a5") + init) == []


def test_reserved_registers_are_configurable(lint):
    source = routine(
        """\
	lea	Table,a4
	lea	Table,a5
	rts
""",
        clobbers="a4/a5",
    )
    assert lint(source, options={"reserved": ["a4"]}) == [
        "main.s:8: error: reserved register a4 is written in Foo"
    ]
    assert lint(source, options={"reserved": []}) == []


def test_only_allow_may_appear_in_a_header(lint):
    source = routine("\trts\n", annotation="; lint: clobbers d0\n")
    assert lint(source) == [
        "main.s:7: error: the lint annotation 'clobbers' cannot be used in a header"
    ]
