"""A routine inherits the clobbers of the routines it calls."""

HELPER = """
;--
; Helper
; In:       d0 = value
; Out:      d0 = result
; Clobbers: d1/a0
Helper:
	move.l	d0,d1
	move.l	d1,a0
	moveq	#0,d0
	rts
"""

CALLER = """
;--
; Caller
; In:       -
; Out:      -
; Clobbers: {clobbers}
Caller:
"""


def caller(body: str, clobbers: str = "-") -> str:
    """Return a routine Caller with the given body; the body starts on line 8."""
    return CALLER.format(clobbers=clobbers) + body


def test_caller_inherits_clobbers_in_the_same_file(lint):
    body = """\
	bsr	Helper
	rts
"""
    assert lint(caller(body, clobbers="d0-d1/a0") + HELPER) == []
    assert lint(caller(body, clobbers="d1") + HELPER) == [
        (
            "main.s:8: error: a0 is clobbered by the call to Helper but not listed"
            " under Out or Clobbers of Caller"
        ),
        (
            "main.s:8: error: d0 is clobbered by the call to Helper but not listed"
            " under Out or Clobbers of Caller"
        ),
    ]


def test_caller_inherits_clobbers_across_files_with_xdef(lint):
    body = """\
	xref	Helper
	jsr	Helper
	rts
"""
    helper = "\txdef\tHelper\n" + HELPER
    assert lint(caller(body, clobbers="d0-d1/a0"), helper_s=helper) == []
    assert lint(caller(body, clobbers="d0-d1"), helper_s=helper) == [
        (
            "main.s:9: error: a0 is clobbered by the call to Helper but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_caller_inherits_clobbers_across_files_from_plain_labels(lint):
    body = """\
	bsr.w	Helper
	rts
"""
    assert lint(caller(body, clobbers="d0-d1"), helper_s=HELPER) == [
        (
            "main.s:8: error: a0 is clobbered by the call to Helper but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_exported_routine_wins_over_private_ones_of_the_same_name(lint):
    body = """\
	bsr	Helper
	rts
"""
    private = """
;--
; Helper
; In:       -
; Out:      -
; Clobbers: a1
Helper:
	move.l	d0,a1
	rts
"""
    exported = "\txdef\tHelper\n" + HELPER
    source = caller(body, clobbers="d0-d1/a0")
    assert lint(source, private_s=private, exported_s=exported) == []
    assert lint(source, private_s=private, other_s=private) == [
        (
            "main.s:8: error: cannot analyse the call to Helper: several files define"
            " a routine of that name"
        )
    ]


def test_call_to_unknown_routine_is_an_error(lint):
    source = caller("""\
	bsr	Mystery
	rts
""")
    assert lint(source) == [
        (
            "main.s:8: error: cannot analyse the call to Mystery: no routine of that"
            " name in the files given"
        )
    ]


def test_call_to_label_without_header_is_an_error(lint):
    source = caller("""\
	bsr	.Sub
	rts
.Sub:
	rts
""")
    assert lint(source) == [
        "main.s:8: error: cannot analyse the call to .Sub: it has no routine header",
        "main.s:11: warning: unreachable code in Caller is not checked",
    ]


def test_annotation_declares_what_an_unknown_routine_clobbers(lint):
    body = """\
	jsr	Mystery		; lint: clobbers d0-d1
	rts
"""
    assert lint(caller(body, clobbers="d0/d1")) == []
    assert lint(caller(body, clobbers="d0")) == [
        (
            "main.s:8: error: d1 is clobbered by the call to Mystery but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_indirect_call_is_an_error_unless_annotated(lint):
    plain = caller("""\
	jsr	(a0)
	jsr	-30(a6)
	rts
""")
    assert lint(plain) == [
        (
            "main.s:8: error: cannot analyse the indirect call jsr (a0); add a"
            " lint: clobbers or lint: targets annotation"
        ),
        (
            "main.s:9: error: cannot analyse the indirect call jsr -30(a6); add a"
            " lint: clobbers or lint: targets annotation"
        ),
    ]
    annotated = caller(
        """\
	jsr	(a0)			; lint: clobbers -
	; The library call preserves all but the scratch registers.
	; lint: clobbers d0-d1/a0-a1
	jsr	-30(a6)
	rts
""",
        clobbers="d0-d1/a0",
    )
    assert lint(annotated) == [
        (
            "main.s:11: error: a1 is clobbered by the indirect call jsr -30(a6) but"
            " not listed under Out or Clobbers of Caller"
        )
    ]


def test_indirect_call_with_listed_targets(lint):
    body = """\
	jsr	(a2)			; lint: targets Helper, Other
	rts

;--
; Other
; In:       -
; Out:      -
; Clobbers: d2
Other:
	moveq	#0,d2
	rts
"""
    assert lint(caller(body, clobbers="d0-d2/a0") + HELPER) == []
    assert lint(caller(body, clobbers="d0-d1/a0") + HELPER) == [
        (
            "main.s:8: error: d2 is clobbered by the call to Other but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_indirect_jump_is_an_error_unless_annotated(lint):
    plain = caller("""\
	jmp	(a0)
""")
    assert lint(plain) == [
        (
            "main.s:8: error: cannot analyse the indirect jump jmp (a0); add a"
            " lint: clobbers or lint: targets annotation"
        )
    ]
    annotated = caller("""\
	jmp	(a0)			; lint: clobbers d3
""")
    assert lint(annotated) == [
        (
            "main.s:8: error: d3 is clobbered by the indirect jump jmp (a0) but not"
            " listed under Out or Clobbers of Caller"
        )
    ]


def test_jump_table_with_local_targets(lint):
    source = caller(
        """\
	move.w	.Table(pc,d0.w),d0
	jmp	.Table(pc,d0.w)		; lint: targets .One, .Two
.Table:
	dc.w	.One-.Table,.Two-.Table
.One:
	moveq	#1,d1
	rts
.Two:
	moveq	#2,d2
	rts
""",
        clobbers="d0",
    )
    assert lint(source) == [
        (
            "main.s:13: error: d1 is written but not listed under Out or Clobbers"
            " of Caller"
        ),
        (
            "main.s:16: error: d2 is written but not listed under Out or Clobbers"
            " of Caller"
        ),
    ]


def test_trap_is_an_error_unless_annotated(lint):
    assert lint(caller("\ttrap\t#0\n\trts\n")) == [
        "main.s:8: error: cannot analyse trap #0; add a lint: clobbers annotation"
    ]
    assert lint(caller("\ttrap\t#0\t; lint: clobbers -\n\trts\n")) == []


def test_tail_call_inherits_clobbers(lint):
    body = """\
	moveq	#0,d2
	bra	Helper
"""
    assert lint(caller(body, clobbers="d0-d2/a0") + HELPER) == []
    assert lint(caller(body, clobbers="d1-d2/a0") + HELPER) == [
        (
            "main.s:9: error: d0 is clobbered by the jump to Helper but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_conditional_tail_call(lint):
    body = """\
	tst.w	Flag
	bne	Helper
	rts
"""
    assert lint(caller(body, clobbers="d1/a0") + HELPER) == [
        (
            "main.s:9: error: d0 is clobbered by the jump to Helper but not listed"
            " under Out or Clobbers of Caller"
        )
    ]


def test_tail_call_needs_a_balanced_stack(lint):
    body = """\
	move.l	d2,-(sp)
	jmp	Helper
"""
    assert lint(caller(body, clobbers="d0-d1/a0") + HELPER) == [
        "main.s:9: error: the stack is not balanced when Caller returns here"
    ]


def test_falling_through_into_the_next_routine_inherits_its_clobbers(lint):
    body = """\
	moveq	#0,d2
"""
    assert lint(caller(body, clobbers="d0-d2/a0") + HELPER) == []
    assert lint(caller(body, clobbers="d0-d2") + HELPER) == [
        (
            "main.s:8: error: a0 is clobbered by falling through into Helper but not"
            " listed under Out or Clobbers of Caller"
        )
    ]


def test_registers_saved_around_a_call_are_preserved(lint):
    body = """\
	movem.l	d0-d1/a0,-(sp)
	bsr	Helper
	movem.l	(sp)+,d0-d1/a0
	rts
"""
    assert lint(caller(body) + HELPER) == []


def test_argument_pushed_for_a_call_and_dropped(lint):
    body = """\
	move.l	d2,-(sp)
	bsr	Helper
	addq.l	#4,sp
	rts
"""
    assert lint(caller(body, clobbers="d0-d1/a0") + HELPER) == []


def test_recursive_routine(lint):
    source = """
;--
; Count
; In:       d0 = count
; Out:      d0 = 0
; Clobbers: -
Count:
	subq.w	#1,d0
	beq	.Done
	bsr	Count
.Done:
	rts
"""
    assert lint(source) == []


def test_unknown_annotation_is_an_error(lint):
    source = caller("""\
	jsr	(a0)			; lint: clobers d0
	; lint: clobbers d0 and d1
	jsr	(a0)
	rts
""")
    assert lint(source) == [
        (
            "main.s:8: error: cannot analyse the indirect call jsr (a0); add a"
            " lint: clobbers or lint: targets annotation"
        ),
        "main.s:8: error: unknown lint annotation 'clobers'",
        "main.s:9: error: cannot parse the lint annotation 'clobbers d0 and d1'",
        (
            "main.s:10: error: cannot analyse the indirect call jsr (a0); add a"
            " lint: clobbers or lint: targets annotation"
        ),
    ]
