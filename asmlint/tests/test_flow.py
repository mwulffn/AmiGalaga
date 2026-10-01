"""Every path through a routine is followed."""

HEADER = """
;--
; Foo
; In:       d0 = value
; Out:      d0 = result
; Clobbers: {clobbers}
Foo:
"""


def routine(body: str, clobbers: str = "-") -> str:
    """Return a routine Foo with the given body; the body starts on line 8."""
    return HEADER.format(clobbers=clobbers) + body


def test_loop_counter_is_written_by_dbf(lint):
    body = """\
	moveq	#0,d0
.Loop:
	add.w	(a0),d0
	dbf	d1,.Loop
	rts
"""
    assert lint(routine(body, clobbers="d1")) == []
    assert lint(routine(body)) == [
        "main.s:11: error: d1 is written but not listed under Out or Clobbers of Foo"
    ]


def test_implicit_writes_are_found(lint):
    source = routine("""\
	move.w	(a0)+,d0
	move.w	d0,-(a1)
	exg	d2,a2
	movem.l	(a3),d3-d4
	rts
""")
    assert lint(source) == [
        "main.s:8: error: a0 is written but not listed under Out or Clobbers of Foo",
        "main.s:9: error: a1 is written but not listed under Out or Clobbers of Foo",
        "main.s:10: error: a2 is written but not listed under Out or Clobbers of Foo",
        "main.s:10: error: d2 is written but not listed under Out or Clobbers of Foo",
        "main.s:11: error: d3 is written but not listed under Out or Clobbers of Foo",
        "main.s:11: error: d4 is written but not listed under Out or Clobbers of Foo",
    ]


def test_write_on_one_branch_is_found(lint):
    source = routine("""\
	tst.w	d0
	beq.s	.Skip
	moveq	#0,d0
	rts
.Skip:
	moveq	#1,d1
	jmp	.Tail(pc)
	moveq	#2,d2
.Tail:
	moveq	#3,d0
	rts
""")
    assert lint(source) == [
        "main.s:13: error: d1 is written but not listed under Out or Clobbers of Foo",
        "main.s:15: warning: unreachable code in Foo is not checked",
    ]


def test_each_exit_may_restore_for_itself(lint):
    source = routine("""\
	movem.l	d2-d3,-(sp)
	move.l	d0,d2
	beq	.Zero
	move.l	d2,d3
	moveq	#1,d0
	movem.l	(sp)+,d2-d3
	rts
.Zero:
	moveq	#0,d0
	movem.l	(sp)+,d2-d3
	rts
""")
    assert lint(source) == []


def test_exit_that_skips_the_restore_is_reported(lint):
    source = routine("""\
	move.l	d2,-(sp)
	move.l	d0,d2
	beq	.Zero
	moveq	#1,d0
	move.l	(sp)+,d2
.Zero:
	rts
""")
    assert lint(source) == [
        "main.s:9: error: d2 is written but not listed under Out or Clobbers of Foo",
        "main.s:14: error: the stack is not balanced when Foo returns here",
    ]


def test_push_inside_a_loop_is_reported(lint):
    source = routine(
        """\
.Loop:
	move.l	d0,-(sp)
	dbf	d1,.Loop
	moveq	#0,d0
	rts
""",
        clobbers="d1",
    )
    assert lint(source) == [
        "main.s:12: error: the stack is not balanced when Foo returns here"
    ]


def test_unknown_label_is_an_error(lint):
    source = routine("""\
	moveq	#0,d0
	bne	.Nowhere
	rts
""")
    assert lint(source) == [
        "main.s:9: error: cannot find the label .Nowhere that Foo branches to"
    ]


def test_local_labels_belong_to_the_preceding_global_label(lint):
    source = routine(
        """\
.Loop:
	addq.w	#1,d0
	dbf	d1,.Loop
FooTail:
.Loop:
	addq.w	#1,d0
	dbf	d2,.Loop
	rts
""",
        clobbers="d1/d2",
    )
    assert lint(source) == []


def test_endless_loop_never_returns(lint):
    source = """
;--
; Main
; In:       -
; Out:      -
; Clobbers: -
Main:
.Forever:
	addq.w	#1,Counter
	bra	.Forever

Counter:
	dc.w	0
"""
    assert lint(source) == []


def test_running_off_the_end_is_an_error(lint):
    source = routine("""\
	moveq	#0,d0
""")
    assert lint(source) == ["main.s:8: error: execution runs off the end of Foo"]


def test_running_into_data_is_an_error(lint):
    source = routine("""\
	moveq	#0,d0
Table:
	dc.w	1,2,3
	rts
""")
    assert lint(source) == [
        "main.s:10: error: execution runs into data in Foo",
        "main.s:11: warning: unreachable code in Foo is not checked",
    ]


def test_unreachable_global_label_is_a_routine_without_header(lint):
    source = routine("""\
	moveq	#0,d0
	rts

Bar:
	moveq	#0,d1
	rts
""")
    assert lint(source) == ["main.s:11: error: Bar has code but no routine header"]


def test_local_labels_ending_in_a_dollar(lint):
    body = """\
loop$:
	addq.w	#1,d0
	dbf	d1,loop$
	rts
"""
    assert lint(routine(body, clobbers="d1")) == []


def test_second_entry_point_needs_a_header_to_be_called(lint):
    source = routine("""\
	moveq	#0,d0
FooTail:
	addq.w	#1,d0
	rts

;--
; Bar
; In:       -
; Out:      -
; Clobbers: d0
Bar:
	bsr	FooTail
	rts
""")
    assert lint(source) == [
        "main.s:19: error: cannot analyse the call to FooTail: it has no routine header"
    ]
